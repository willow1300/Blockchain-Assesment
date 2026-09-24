use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount};
use anchor_lang::system_program::System;

// how this airdrop is meant to work:
// 1. admin calls initialize once: pot size + time window + max users
// 2. admin whitelists wallets that can claim
// 3. during the window each whitelisted wallet claims once
// 4. payout per wallet is an equal share: total / headcount
//
// the old version kept a HashSet on-chain (doesn't serialize under
// borsh), let anyone whitelist themselves, and let one wallet claim
// again and again. all three are fixed below.

#[program]
pub mod airdrop {
    use super::*;

    // set up the airdrop. caller becomes the authority, only they can
    // add wallets to the whitelist afterwards.
    pub fn initialize(
        ctx: Context<Initialize>,
        total_tokens: u64,
        start_time: i64,
        duration: i64,
        max_users: u32,
    ) -> Result<()> {
        // no point deploying an airdrop with nothing in it
        require!(total_tokens > 0, AirdropError::EmptySupply);
        require!(duration > 0, AirdropError::BadDuration);
        require!(max_users > 0, AirdropError::NoRoomForUsers);

        let state = &mut ctx.accounts.airdrop_account;
        state.authority = ctx.accounts.authority.key();
        state.start_time = start_time;
        // checked so a bad duration can't wrap the timestamp
        state.end_time = start_time.checked_add(duration).ok_or(AirdropError::BadDuration)?;
        state.total_tokens = total_tokens;
        state.distributed_tokens = 0;
        state.max_users = max_users;
        state.whitelisted = Vec::with_capacity(max_users as usize);
        state.claimed = Vec::with_capacity(max_users as usize);

        Ok(())
    }

    // admin-only. adds one wallet. has to happen before claims, and the
    // list caps at max_users so the account never outgrows its space.
    pub fn whitelist_user(ctx: Context<WhitelistUser>) -> Result<()> {
        let state = &mut ctx.accounts.airdrop_account;
        let user = ctx.accounts.user.key();

        // linear scan is fine, lists are small and capped
        require!(!state.whitelisted.contains(&user), AirdropError::AlreadyWhitelisted);
        require!((state.whitelisted.len() as u32) < state.max_users, AirdropError::WhitelistFull);

        state.whitelisted.push(user);
        // keep claimed flags lined up 1:1 with the whitelist
        state.claimed.push(false);

        emit!(UserWhitelisted { user });
        Ok(())
    }

    // pays out one share to the recipient. anyone can call it, but the
    // recipient must be whitelisted, inside the window, and unclaimed.
    pub fn distribute_airdrop(ctx: Context<DistributeAirdrop>) -> Result<()> {
        let state = &mut ctx.accounts.airdrop_account;
        let now = Clock::get()?.unix_timestamp;

        require!(now >= state.start_time, AirdropError::NotStarted);
        require!(now < state.end_time, AirdropError::AlreadyEnded);

        let recipient = ctx.accounts.recipient.key();
        let slot = state
            .whitelisted
            .iter()
            .position(|w| *w == recipient)
            .ok_or(AirdropError::NotWhitelisted)?;

        // the double-claim fix: without this the same wallet could call
        // again and again until the pot is drained
        require!(!state.claimed[slot], AirdropError::AlreadyClaimed);

        let headcount = state.whitelisted.len() as u64;
        require!(headcount > 0, AirdropError::NobodyWhitelisted);

        // equal split. dust caveat: total / headcount truncates, so if it
        // doesn't divide evenly a few base units stay stuck. sweeping those
        // or switching to a fixed amount per user is a product call.
        let share = state.total_tokens.checked_div(headcount).ok_or(AirdropError::MathError)?;
        require!(share > 0, AirdropError::ShareIsZero);

        state.distributed_tokens = state
            .distributed_tokens
            .checked_add(share)
            .ok_or(AirdropError::MathError)?;
        require!(state.distributed_tokens <= state.total_tokens, AirdropError::OverAllocated);

        // mark claimed before the CPI so a failed transfer never
        // looks unclaimed afterwards
        state.claimed[slot] = true;

        let cpi_accounts = token::Transfer {
            from: ctx.accounts.airdrop_token_account.to_account_info(),
            to: ctx.accounts.recipient_token_account.to_account_info(),
            authority: ctx.accounts.authority.to_account_info(),
        };
        token::transfer(
            CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts),
            share,
        )?;

        emit!(TokenDistributed { recipient, amount: share });
        Ok(())
    }
}

#[derive(Accounts)]
#[instruction(total_tokens: u64, start_time: i64, duration: i64, max_users: u32)]
pub struct Initialize<'info> {
    // 8 discriminator + authority(32) + start(8) + end(8) + total(8)
    // + distributed(8) + max_users(4) + whitelist(4 + 32*max)
    // + claimed(4 + 1*max). sized from max_users, no hardcoded 1000.
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 8 + 8 + 8 + 8 + 4 + (4 + 32 * max_users as usize) + (4 + max_users as usize)
    )]
    pub airdrop_account: Account<'info, AirdropAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct WhitelistUser<'info> {
    // only the authority from initialize can add wallets. this closes
    // the old hole where anyone could whitelist themselves.
    #[account(mut, has_one = authority)]
    pub airdrop_account: Account<'info, AirdropAccount>,
    pub authority: Signer<'info>,
    /// CHECK: plain pubkey going into the list, nothing read from it.
    pub user: UncheckedAccount<'info>,
}

#[derive(Accounts)]
pub struct DistributeAirdrop<'info> {
    #[account(mut, has_one = authority)]
    pub airdrop_account: Account<'info, AirdropAccount>,
    // vault holding the tokens. must be owned by the authority or the
    // transfer CPI fails, which is exactly what we want.
    #[account(mut, token::mint = mint, token::authority = authority)]
    pub airdrop_token_account: Account<'info, TokenAccount>,
    // recipient's account for the same mint, owned by the recipient.
    // whitelist check below ties it to an approved wallet.
    #[account(mut, token::mint = mint, token::authority = recipient)]
    pub recipient_token_account: Account<'info, TokenAccount>,
    /// CHECK: whitelisted wallet being paid, nothing read from it.
    pub recipient: UncheckedAccount<'info>,
    pub authority: Signer<'info>,
    pub mint: Account<'info, anchor_spl::token::Mint>,
    pub token_program: Program<'info, Token>,
}

// on-chain state for one airdrop
#[account]
pub struct AirdropAccount {
    // set once in initialize, gates whitelisting
    pub authority: Pubkey,
    pub start_time: i64,
    pub end_time: i64,
    pub total_tokens: u64,
    pub distributed_tokens: u64,
    // cap so the account can't outgrow its allocation
    pub max_users: u32,
    // whitelisted wallets, same order as claimed flags
    pub whitelisted: Vec<Pubkey>,
    // claimed[i] turns true once whitelisted[i] has been paid
    pub claimed: Vec<bool>,
}

#[error_code]
pub enum AirdropError {
    #[msg("Total supply has to be more than zero.")]
    EmptySupply,
    #[msg("Duration has to be positive, and start + duration must not overflow.")]
    BadDuration,
    #[msg("Max users has to be at least one.")]
    NoRoomForUsers,
    #[msg("Wallet is already whitelisted.")]
    AlreadyWhitelisted,
    #[msg("Whitelist is full.")]
    WhitelistFull,
    #[msg("Airdrop has not started yet.")]
    NotStarted,
    #[msg("Airdrop window is over.")]
    AlreadyEnded,
    #[msg("Wallet is not on the whitelist.")]
    NotWhitelisted,
    #[msg("Wallet already claimed its share.")]
    AlreadyClaimed,
    #[msg("Nobody is whitelisted yet.")]
    NobodyWhitelisted,
    #[msg("Share would be zero, nothing to pay out.")]
    ShareIsZero,
    #[msg("Payout would exceed the allocated supply.")]
    OverAllocated,
    #[msg("Math overflow or divide by zero.")]
    MathError,
}

#[event]
pub struct UserWhitelisted {
    #[index]
    pub user: Pubkey,
}

#[event]
pub struct TokenDistributed {
    #[index]
    pub recipient: Pubkey,
    pub amount: u64,
}
