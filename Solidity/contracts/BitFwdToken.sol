// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

/// @title BitFwdToken (FWD) — documented update of the archived BokkyPooBah example.
/// @notice ERC-20 with owner-controlled minting until `disableMinting()` permanently closes it.
/// @dev Pinned to solc 0.5.17 (last 0.5.x). A future upgrade should target ^0.8.x + OpenZeppelin.
///      Supply starts at 0. No cap: owner can mint any amount while `mintable` is true — documented as the inherited risk.

/// @title SafeMath — overflow-checked arithmetic for uint256.
/// @dev `internal` so calls are inlined (no external library linking, cheaper than `public`).
library SafeMath {
    /// @notice Adds two numbers, reverting on overflow.
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /// @notice Subtracts two numbers, reverting on underflow.
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /// @notice Multiplies two numbers, reverting on overflow.
    /// @dev Gas optimisation: short-circuits when `a == 0` instead of running the division check.
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /// @notice Divides two numbers, reverting on division by zero.
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }
}

/// @title ERC20Interface — the ERC-20 standard surface this token implements.
/// @dev Function declarations only; events mirror EIP-20.
contract ERC20Interface {
    function totalSupply() public view returns (uint256);
    function balanceOf(address tokenOwner) public view returns (uint256 balance);
    function allowance(address tokenOwner, address spender) public view returns (uint256 remaining);
    function transfer(address to, uint256 tokens) public returns (bool success);
    function approve(address spender, uint256 tokens) public returns (bool success);
    function transferFrom(address from, address to, uint256 tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);
}

/// @title ApproveAndCallFallBack — callback a spender contract must expose for `approveAndCall`.
/// @dev Calling an untrusted contract here is a trust/risk decision; see `approveAndCall` docs.
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes memory data) public;
}

/// @title Owned — two-step ownership transfer.
/// @notice `transferOwnership` nominates; `acceptOwnership` completes. Prevents locking by typo.
/// @dev CRITICAL for this token: ownership == minting power. Whoever holds `owner` can mint
///      unlimited tokens until `disableMinting()`. Transfer ownership only to a trusted party/multisig.
contract Owned {
    address public owner;
    address public newOwner;

    /// @notice Emitted when ownership moves from one account to another.
    event OwnershipTransferred(address indexed _from, address indexed _to);

    /// @dev Deployer becomes the first owner — and therefore the first minter.
    constructor() public { owner = msg.sender; }

    /// @notice Restricts a function to the current owner.
    modifier onlyOwner {
        require(msg.sender == owner, "Owned: caller is not the owner");
        _;
    }

    /// @notice Nominates a new owner. Does not take effect until accepted.
    /// @param _newOwner The nominee; zero address is rejected so mint control can't be burned by mistake.
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Owned: zero address");
        newOwner = _newOwner;
    }

    /// @notice Completes the handover. Only the nominee can call.
    /// @dev Resets `newOwner` to zero so a stale nomination can't be replayed.
    function acceptOwnership() public {
        require(msg.sender == newOwner, "Owned: caller is not pending owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

/// @title BitFwdToken — mintable ERC-20 (FWD, 18 decimals), supply starts at zero.
/// @notice Owner mints via `mint()`; anyone can verify the window closed via `mintable == false`.
/// @dev No cap by design (faithful to archive). If a cap is ever wanted, add an immutable `CAP`
///      and `require(_totalSupply.add(tokens) <= CAP)` in `mint()` — that changes economics, so not done here.
contract BitFwdToken is ERC20Interface, Owned {
    using SafeMath for uint256;

    string public symbol;
    string public name;
    uint8 public decimals;

    /// @dev Private; read via `totalSupply()`.
    uint256 private _totalSupply;

    /// @notice True while `mint()` is callable. Set false forever by `disableMinting()`.
    bool public mintable;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;

    /// @notice Emitted once, when the owner permanently closes minting.
    event MintingDisabled();

    /// @notice Deploys with FWD metadata and opens the minting window. No tokens exist yet.
    constructor() public {
        symbol = "FWD";
        name = "BitFwd Token";
        decimals = 18;
        mintable = true;
    }

    /// @notice Returns circulating supply, treating zero-address holdings as burned.
    function totalSupply() public view returns (uint256) {
        return _totalSupply.sub(balances[address(0)]);
    }

    /// @notice Permanently closes minting. One-way: no re-enable exists.
    function disableMinting() public onlyOwner {
        require(mintable, "BitFwd: minting already disabled");
        mintable = false;
        emit MintingDisabled();
    }

    /// @notice Returns the token balance of `tokenOwner`.
    function balanceOf(address tokenOwner) public view returns (uint256 balance) {
        return balances[tokenOwner];
    }

    /// @notice Moves `tokens` from caller to `to`. Reverts on insufficient balance or zero recipient.
    /// @dev Zero-address guard added vs archive (burns must go through intended paths, not typos).
    function transfer(address to, uint256 tokens) public returns (bool success) {
        require(to != address(0), "ERC20: transfer to zero address");
        balances[msg.sender] = balances[msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(msg.sender, to, tokens);
        return true;
    }

    /// @notice Sets `spender`'s allowance to `tokens`, overwriting any previous value.
    /// @dev KNOWN RISK (unchanged from archive): allowance front-running race — changing N→M
    ///      can be sandwiched so the spender spends both. Mitigate off-chain (set to 0 first,
    ///      or use increase/decrease allowance variants in a future version).
    function approve(address spender, uint256 tokens) public returns (bool success) {
        require(spender != address(0), "ERC20: approve to zero address");
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    /// @notice Moves `tokens` from `from` to `to`, spending caller's allowance. Reverts if over balance/allowance.
    function transferFrom(address from, address to, uint256 tokens) public returns (bool success) {
        require(to != address(0), "ERC20: transfer to zero address");
        balances[from] = balances[from].sub(tokens);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);
        emit Transfer(from, to, tokens);
        return true;
    }

    /// @notice Returns remaining tokens `spender` may pull from `tokenOwner`.
    function allowance(address tokenOwner, address spender) public view returns (uint256 remaining) {
        return allowed[tokenOwner][spender];
    }

    /// @notice Approves `spender` then calls its `receiveApproval` in one transaction (MiniMe pattern).
    /// @dev TRUST WARNING (unchanged from archive): hands control to untrusted `spender` code,
    ///      which can re-enter before returning. Only use with vetted spender contracts.
    /// @param data Opaque payload forwarded to the spender.
    function approveAndCall(address spender, uint256 tokens, bytes memory data) public returns (bool success) {
        require(spender != address(0), "ERC20: zero spender");
        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);
        ApproveAndCallFallBack(spender).receiveApproval(msg.sender, tokens, address(this), data);
        return true;
    }

    /// @notice Mints `tokens` to `tokenOwner` and grows `_totalSupply`. Owner-only, only while `mintable`.
    /// @dev Gate on `mintable` first (cheapest revert), then zero-address, then effects + mint event.
    ///      START VALUE: supply begins at 0 — this is `mintable` design, not `fixedSupply` design.
    function mint(address tokenOwner, uint256 tokens) public onlyOwner returns (bool success) {
        require(mintable, "BitFwd: minting disabled");
        require(tokenOwner != address(0), "BitFwd: cannot mint to zero address");
        balances[tokenOwner] = balances[tokenOwner].add(tokens);
        _totalSupply = _totalSupply.add(tokens);
        emit Transfer(address(0), tokenOwner, tokens);
        return true;
    }

    /// @notice Rejects all plain ETH transfers to this contract.
    function () external payable { revert(); }

    /// @notice Owner-only rescue: pulls ERC-20 tokens accidentally sent to this contract out to `owner`.
    /// @dev Zero-address token guard added so a typo can't silently no-op.
    ///      Return value is propagated, not `require`d (unchanged from archive).
    function transferAnyERC20Token(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
        require(tokenAddress != address(0), "Invalid token address");
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}

