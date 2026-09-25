use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};
use anchor_lang::system_program::{self, System};

// presale in three tiers:
// first 50b tokens at 100 lamports each, next 50b at 200, last 50b at 300.
// buyer pays SOL into a vault, gets freshly minted tokens back.
// everything is integer math, no floats anywhere.

#[program]
pub mod presale {
    use super::*;

    // price per token in lamports, per tier
    const PRICE_TIER_1: u64 = 100;
    const PRICE_TIER_2: u64 = 200;
    const PRICE_TIER_3: u64 = 300;
    // where each tier tops out (in base units, before decimals)
    const TIER_1_CAP: u64 = 50_000_000_000;
    const TIER_2_CAP: u64 = 100_000_000_000;
    const TIER_3_CAP: u64 = 150_000_000_000;

    pub fn buy_tokens(ctx: Context<BuyTokens>, amount: u64) -> Result<()> {
        // can't buy nothing
        require!(amount > 0, PresaleError::InvalidAmount);

        let state = &mut ctx.accounts.presale_account;

        // figure out where this purchase starts. anything past the last
        // cap means the sale is done.
        let start = state.total_sold;
        require!(start < TIER_3_CAP, PresaleError::PresaleEnded);

        // walk through the tiers so an order crossing a boundary pays
        // each chunk at the right price. old version picked one price
        // for the whole order, which undercharged big buys.
        let mut left = amount;
        let mut cursor = start;
        let mut cost: u64 = 0;
        while left > 0 {
            let (cap, price) = if cursor < TIER_1_CAP {
                (TIER_1_CAP, PRICE_TIER_1)
            } else if cursor < TIER_2_CAP {
                (TIER_2_CAP, PRICE_TIER_2)
            } else if cursor < TIER_3_CAP {
                (TIER_3_CAP, PRICE_TIER_3)
            } else {
                return Err(error!(PresaleError::PresaleEnded));
            };

            let room = cap - cursor;
            let take = left.min(room);
            let chunk_cost = take.checked_mul(price).ok_or(PresaleError::MathError)?;
            cost = cost.checked_add(chunk_cost).ok_or(PresaleError::MathError)?;

            cursor = cursor.checked_add(take).ok_or(PresaleError::MathError)?;
            left -= take;
        }

        // buyer -> vault. old code only checked the buyer's balance and
        // never moved any SOL, so tokens were free. this actually moves it.
        let pay_ctx = CpiContext::new(
            ctx.accounts.system_program.to_account_info(),
            system_program::Transfer {
                from: ctx.accounts.buyer.to_account_info(),
                to: ctx.accounts.vault.to_account_info(),
            },
        );
        system_program::transfer(pay_ctx, cost)?;

        // mint the tokens to the buyer's account. mint authority is the
        // presale signer stored on the state, checked with has_one below.
        let mint_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            token::MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.buyer_token_account.to_account_info(),
                authority: ctx.accounts.authority.to_account_info(),
            },
        );
        token::mint_to(mint_ctx, amount)?;

        // finally bump the sold counter
        state.total_sold = state
            .total_sold
            .checked_add(amount)
            .ok_or(PresaleError::MathError)?;

        emit!(TokensBought {
            buyer: ctx.accounts.buyer.key(),
            amount,
            cost,
        });
        Ok(())
    }
}

#[derive(Accounts)]
pub struct BuyTokens<'info> {
    #[account(mut, has_one = authority, has_one = mint)]
    pub presale_account: Account<'info, PresaleAccount>,
    // buyer's token account for this mint
    #[account(mut, token::mint = mint, token::authority = buyer)]
    pub buyer_token_account: Account<'info, TokenAccount>,
    #[account(mut, mint::authority = authority)]
    pub mint: Account<'info, Mint>,
    // pays SOL and receives tokens
    #[account(mut)]
    pub buyer: Signer<'info>,
    // holds the mint authority keys, signs the mint
    pub authority: Signer<'info>,
    // where the SOL goes. plain system account, checked by address
    // on the client side.
    /// CHECK: vault receiving SOL, no data read from it.
    #[account(mut)]
    pub vault: UncheckedAccount<'info>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[account]
pub struct PresaleAccount {
    // mint this sale sells
    pub mint: Pubkey,
    // signer allowed to mint for the sale
    pub authority: Pubkey,
    pub total_sold: u64,
}

#[error_code]
pub enum PresaleError {
    #[msg("Presale is over.")]
    PresaleEnded,
    #[msg("Amount has to be more than zero.")]
    InvalidAmount,
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
