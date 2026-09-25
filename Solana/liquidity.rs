use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};
use anchor_lang::system_program::System;

// simple liquidity pot:
// admin stocks it once, buyers pay SOL at a fixed price and get tokens.
// the token side is a vault owned by the state authority.

#[program]
pub mod liquidity {
    use super::*;

    // create the state. caller becomes the authority.
    pub fn initialize(
        ctx: Context<Initialize>,
        total_liquidity: u64,
        price_per_token: u64,
    ) -> Result<()> {
        // empty pot or free tokens, neither makes sense
        require!(total_liquidity > 0, LiquidityError::BadAmount);
        require!(price_per_token > 0, LiquidityError::BadPrice);

        let state = &mut ctx.accounts.state;
        state.authority = ctx.accounts.authority.key();
        state.mint = ctx.accounts.mint.key();
        state.total_liquidity = total_liquidity;
        state.sold_tokens = 0;
        state.price_per_token = price_per_token;

        Ok(())
    }

    // buy `amount` tokens. SOL goes to the vault, tokens come from
    // the vault token account. both move or neither does.
    pub fn purchase_tokens(ctx: Context<PurchaseTokens>, amount: u64) -> Result<()> {
        require!(amount > 0, LiquidityError::BadAmount);

        let state = &mut ctx.accounts.state;

        // enough left in the pot?
        let remaining = state
            .total_liquidity
            .checked_sub(state.sold_tokens)
            .ok_or(LiquidityError::MathError)?;
        require!(amount <= remaining, LiquidityError::NotEnoughLiquidity);

        // fixed price, checked so big orders can't wrap around
        let cost = amount.checked_mul(state.price_per_token).ok_or(LiquidityError::MathError)?;

        // buyer pays SOL first. old version skipped this entirely and
        // just edited two numbers, so anyone could drain the accounting
        // for free.
        let pay_ctx = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            anchor_lang::system_program::Transfer {
                from: ctx.accounts.buyer.to_account_info(),
                to: ctx.accounts.vault.to_account_info(),
            },
        );
        anchor_lang::system_program::transfer(pay_ctx, cost)?;

        // then tokens go the other way, vault -> buyer
        let bump = ctx.bumps.state;
        let seeds: &[&[u8]] = &[
            b"liquidity",
            ctx.accounts.mint.key().as_ref(),
            &[bump],
        ];
        let signer_seeds: &[&[&[u8]]] = &[seeds];
        let token_ctx = CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            token::Transfer {
                from: ctx.accounts.vault_token_account.to_account_info(),
                to: ctx.accounts.buyer_token_account.to_account_info(),
                authority: ctx.accounts.state.to_account_info(),
            },
            signer_seeds,
        );
        token::transfer(token_ctx, amount)?;

        state.sold_tokens = state.sold_tokens.checked_add(amount).ok_or(LiquidityError::MathError)?;

        emit!(TokensBought {
            buyer: ctx.accounts.buyer.key(),
            amount,
            cost,
        });
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    // PDA so only this program can sign for the vault later.
    // space: 8 + authority(32) + mint(32) + liquidity(8) + sold(8) + price(8)
    #[account(
        init,
        payer = authority,
        space = 8 + 32 + 32 + 8 + 8 + 8,
        seeds = [b"liquidity", mint.key().as_ref()],
        bump,
    )]
    pub state: Account<'info, LiquidityState>,
    pub mint: Account<'info, Mint>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct PurchaseTokens<'info> {
    // has_one checks tie the state to the right mint + authority,
    // token constraints tie both token accounts to the same mint.
    #[account(mut, has_one = authority, has_one = mint)]
    pub state: Account<'info, LiquidityState>,
    /// CHECK: stored on state, signs the token transfer via PDA seeds.
    pub authority: UncheckedAccount<'info>,
    pub mint: Account<'info, Mint>,
    // vault holding the tokens, owned by the state PDA
    #[account(mut, token::mint = mint, token::authority = state)]
    pub vault_token_account: Account<'info, TokenAccount>,
    // buyer's account for the same mint
    #[account(mut, token::mint = mint, token::authority = buyer)]
    pub buyer_token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub buyer: Signer<'info>,
    // where the SOL ends up
    /// CHECK: plain SOL vault, nothing read from it.
    #[account(mut)]
    pub vault: UncheckedAccount<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct LiquidityState {
    // admin, set once
    pub authority: Pubkey,
    // which mint this pot sells
    pub mint: Pubkey,
    // how many tokens the pot started with
    pub total_liquidity: u64,
    // how many have been sold so far
    pub sold_tokens: u64,
    // fixed price in lamports per token
    pub price_per_token: u64,
}

#[error_code]
pub enum LiquidityError {
    #[msg("Amount has to be more than zero.")]
    BadAmount,
    #[msg("Price has to be more than zero.")]
    BadPrice,
    #[msg("Not enough liquidity left for that amount.")]
    NotEnoughLiquidity,
    #[msg("Math overflow.")]
    MathError,
}

#[event]
pub struct TokensBought {
    #[index]
    pub buyer: Pubkey,
    pub amount: u64,
    pub cost: u64,
}