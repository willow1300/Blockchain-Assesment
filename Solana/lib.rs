use anchor_lang::prelude::*;

// program id - replace this before you deploy.
// run `anchor keys list` after `anchor build` and paste it here.
declare_id!("Your_Program_ID_Here");

// each file is its own little piece. note: anchor really wants one
// program per crate, so if you keep them all in here like this you'll
// get clashes (every file has its own Initialize, its own errors...).
// long term either merge them into one #[program] or split each into
// its own crate. for now this just wires the modules up.
pub mod token;
pub mod airdrop;
pub mod presale;
pub mod dev_fund;
pub mod liquidity;