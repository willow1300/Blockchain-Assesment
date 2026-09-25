use anchor_lang::prelude::*;
use anchor_spl::token::{self, Mint, Token, TokenAccount};
use anchor_lang::system_program::System;

// basic token setup:
// creates a new mint (9 decimals) and mints the full supply to one
// token account owned by the authority. that's it, no minting after.

#[program]
pub mod token {
    use super::*;

    // authority pays for both accounts and ends up holding everything.
    pub fn initialize(ctx: Context<Initialize>, total_supply: u64) -> Result<()> {
        // zero supply mint makes no sense, bail early
        require!(total_supply > 0, TokenError::InvalidSupply);

        // set up the mint itself. no freeze authority, authority stays
        // as the mint authority.
        let init_mint_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            token::InitializeMint {
                mint: ctx.accounts.mint.to_account_info(),
                rent: ctx.accounts.rent.to_account_info(),
            },
        );
        token::initialize_mint(
            init_mint_ctx,
            9,
            &ctx.accounts.authority.key(),
            None,
        )?;

        // now mint the whole supply to the authority's token account
        let mint_to_ctx = CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            token::MintTo {
                mint: ctx.accounts.mint.to_account_info(),
                to: ctx.accounts.token_account.to_account_info(),
                authority: ctx.accounts.authority.to_account_info(),
            },
        );
        token::mint_to(mint_to_ctx, total_supply)?;

        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    // fresh mint, authority pays for it
    #[account(init, payer = authority, mint::decimals = 9, mint::authority = authority)]
    pub mint: Account<'info, Mint>,
    // fresh token account for that mint, owned by the authority.
    // the constraints tie it to the mint above so you can't pass
    // in some random account here.
    #[account(
        init,
        payer = authority,
        token::mint = mint,
        token::authority = authority,
    )]
    pub token_account: Account<'info, TokenAccount>,
    #[account(mut)]
    pub authority: Signer<'info>,
    pub rent: Sysvar<'info, Rent>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[error_code]
pub enum TokenError {
    #[msg("Supply has to be more than zero.")]
    InvalidSupply,
}