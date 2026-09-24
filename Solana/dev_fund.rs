use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};
use anchor_lang::system_program::System;

// dev fund with linear vesting over 24 months.
// admin locks an amount once, then pulls out what's unlocked over time.
// unlocked = total_allocated * months_passed / 24.
//
// old version had the month math wrong (divided by seconds-in-a-year,
// so vesting ran ~12x too slow), let allocate be called again to reset
// the clock, and referenced accounts that didn't exist. fixed below.

#[program]
pub mod dev_fund {
    use super::*;

    // 24 months, using 30-day months. not exact calendar months but
    // close enough and predictable on-chain.
    const MONTHS: u64 = 24;
    const SECS_PER_MONTH: i64 = 30 * 24 * 60 * 60;

    // lock tokens once. caller becomes the authority.
    pub fn allocate_tokens(ctx: Context<AllocateTokens>, amount: u64) -> Result<()> {
        // nothing to vest
        require!(amount > 0, DevFundError::BadAmount);

        let fund = &mut ctx.accounts.fund_account;
        fund.authority = ctx.accounts.authority.key();
        fund.mint = ctx.accounts.mint.key();
        fund.total_allocated = amount;
        fund.total_released = 0;
        fund.start_time = Clock::get()?.unix_timestamp;

        // init only runs once per PDA, so no way to reset the clock
        // by calling this again. that's on purpose.
        Ok(())
    }

    // pay out whatever's unlocked but not yet released.
    pub fn release_tokens(ctx: Context<ReleaseTokens>) -> Result<()> {
        let fund = &mut ctx.accounts.fund_account;
        let now = Clock::get()?.unix_timestamp;

        // clock shouldn't be behind start, but don't underflow if it is
        let elapsed_secs = now.checked_sub(fund.start_time).ok_or(DevFundError::MathError)?;
        require!(elapsed_secs >= 0, DevFundError::NothingUnlocked);

        // whole months passed, capped at 24
        let mut months = (elapsed_secs / SECS_PER_MONTH) as u64;
        if months > MONTHS {
            months = MONTHS;
        }

        // pro-rata from the actual allocation, not a hardcoded 100b.
        // old code used a fixed per-month number so dust got stuck and
        // custom amounts didn't vest right.
        let releasable = fund
            .total_allocated
            .checked_mul(months)
            .ok_or(DevFundError::MathError)?
            .checked_div(MONTHS)
            .ok_or(DevFundError::MathError)?;

        require!(releasable > fund.total_released, DevFundError::NothingUnlocked);
        let payout = releasable - fund.total_released;

        // vault -> recipient, signed by the fund PDA
        let bump = ctx.bumps.fund_account;
        let seeds: &[&[u8]] = &[
            b"dev-fund",
            ctx.accounts.authority.key().as_ref(),
            ctx.accounts.mint.key().as_ref(),
            &[bump],
        ];
        let signer: &[&[&[u8]]] = &[seeds];
        let cpi_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            token::Transfer {
                from: ctx.accounts.vault_token_account.to_account_info(),
                to: ctx.accounts.recipient_token_account.to_account_info(),
                authority: ctx.accounts.fund_account.to_account_info(),
            },
            signer,
        );
        token::transfer(cpi_ctx, payout)?;

        fund.total_released = fund.total_released.checked_add(payout).ok_or(DevFundError::MathError)?;

        emit!(TokensReleased {
            to: ctx.accounts.recipient.key(),
            amount: payout,
        });
        Ok(())
    }
}

#[derive(Accounts)]
pub struct AllocateTokens<'info> {
    // PDA so there's exactly one fund per (authority, mint).
    // space: 8 + authority(32) + mint(32) + allocated(8) + released(8) + start(8)
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 8 + 8,
        seeds = [b"dev-fund", authority.key().as_ref(), mint.key().as_ref()],
        bump,
    )]
    pub fund_account: Account<'info, FundAccount>,
    pub mint: Account<'info, Mint>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ReleaseTokens<'info> {
    // has_one ties it to the right mint + authority
    #[account(mut, has_one = authority, has_one = mint)]
    pub fund_account: Account<'info, FundAccount>,
    // vault holding the locked tokens, owned by the fund PDA
    #[account(mut, token::mint = mint, token::authority = fund_account)]
    pub vault_token_account: Account<'info, TokenAccount>,
    // where the unlocked tokens go
    #[account(mut, token::mint = mint)]
    pub recipient_token_account: Account<'info, TokenAccount>,
    /// CHECK: wallet owning the recipient token account.
    pub recipient: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub mint: Account<'info, Mint>,
    pub token_program: Program<'info, Token>,
}

#[account]
pub struct FundAccount {
    // who can trigger releases, set once
    pub authority: Pubkey,
    // which mint is vesting
    pub mint: Pubkey,
    pub total_allocated: u64,
    pub total_released: u64,
    pub start_time: i64,
}

#[error_code]
pub enum DevFundError {
    #[msg("Amount has to be more than zero.")]
    BadAmount,
    #[msg("Nothing unlocked yet.")]
    NothingUnlocked,
    #[msg("Math overflow.")]
    MathError,
}

#[event]
pub struct TokensReleased {
    #[index]
    pub to: Pubkey,
    pub amount: u64,
}