// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

/// @title FlexibleToken — documented update of the archived BokkyPooBah example.
/// @notice ERC-20 whose symbol/name the owner can edit until `lock()` permanently freezes them.
/// @dev Pinned to solc 0.5.17 (last 0.5.x). A future upgrade should target ^0.8.x + OpenZeppelin.
///      RESTORED vs your draft: the `locked` flag, `lock()`, `setSymbol()`, `setName()` and their
///      events — without them this is a generic token, not the "flexible" one.

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
    function balanceOf(address tokenOwner) public view returns (uint256);
    function allowance(address tokenOwner, address spender) public view returns (uint256);
    function transfer(address to, uint256 tokens) public returns (bool);
    function approve(address spender, uint256 tokens) public returns (bool);
    function transferFrom(address from, address to, uint256 tokens) public returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint256 tokens);
}

/// @title ApproveAndCallFallBack — callback a spender contract must expose for `approveAndCall`.
/// @dev Calling an untrusted contract here is a trust/risk decision; see `approveAndCall` docs.
contract ApproveAndCallFallBack {
    function receiveApproval(
        address from,
        uint256 tokens,
        address token,
        bytes memory data
    ) public;
}

/// @title Owned — two-step ownership transfer.
/// @notice `transferOwnership` nominates; `acceptOwnership` completes. Prevents locking by typo.
/// @dev Ownership gates `transferAnyERC20Token` and the metadata functions. ERC-20 transfers are permissionless.
contract Owned {
    address public owner;
    address public newOwner;

    /// @notice Emitted when ownership moves from one account to another.
    event OwnershipTransferred(address indexed _from, address indexed _to);

    /// @dev Deployer becomes the first owner.
    constructor() public {
        owner = msg.sender;
    }

    /// @notice Restricts a function to the current owner.
    modifier onlyOwner() {
        require(msg.sender == owner, "Owned: caller is not the owner");
        _;
    }

    /// @notice Nominates a new owner. Does not take effect until accepted.
    /// @param _newOwner The nominee; zero address is rejected so ownership can't be burned by mistake.
    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0), "Owned: zero address");
        newOwner = _newOwner;
    }

    /// @notice Completes the handover. Only the nominee can call.
    /// @dev Resets `newOwner` to zero so a stale nomination can't be replayed.
    function acceptOwnership() public {
        require(msg.sender == newOwner, "Owned: not nominated owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

/// @title FlexibleToken — ERC-20 with owner-editable symbol/name until permanently locked.
/// @notice Supply is fixed at deployment (`_initialSupply`, minted to `owner`); only metadata is flexible.
/// @dev `locked` starts false. `lock()` flips it true forever; `setSymbol`/`setName` revert once locked.
///      TRUST NOTE: explorers/wallets may cache the old symbol/name, so users can be shown stale metadata.
contract FlexibleToken is ERC20Interface, Owned {
    using SafeMath for uint256;

    string public symbol;
    string public name;
    uint8 public decimals;
    uint256 private _totalSupply;

    /// @notice True once `lock()` is called; metadata can never change again.
    bool public locked = false;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;

    /// @notice Emitted when metadata is permanently frozen.
    event Locked();
    /// @notice Emitted on each symbol change, carrying old and new values for indexers.
    event SymbolUpdated(string oldSymbol, string newSymbol);
    /// @notice Emitted on each name change, carrying old and new values for indexers.
    event NameUpdated(string oldName, string newName);
    /// @notice Deploys the token with caller-chosen metadata and fixed supply minted to the deployer (owner).
    /// @dev IMPROVEMENT over archive: rejects empty symbol/name at deploy so the token can't start nameless.
    /// @param _symbol Ticker, e.g. "FLX". @param _name Full name, e.g. "FlexibleToken".
    /// @param _decimals Decimals, e.g. 18. @param _initialSupply Total supply in base units (already scaled).
    constructor(
        string memory _symbol,
        string memory _name,
        uint8 _decimals,
        uint256 _initialSupply
    ) public {
        require(bytes(_symbol).length > 0, "Empty symbol");
        require(bytes(_name).length > 0, "Empty name");

        symbol = _symbol;
        name = _name;
        decimals = _decimals;
        _totalSupply = _initialSupply;

        balances[owner] = _totalSupply;
        emit Transfer(address(0), owner, _totalSupply);
    }

    /// @notice Permanently freezes symbol/name. One-way: no unlock exists.
    /// @dev Emits `Locked` before flipping the flag (archive order kept).
    function lock() public onlyOwner {
        require(!locked, "FlexibleToken: already locked");
        emit Locked();
        locked = true;
    }

    /// @notice Replaces the ticker. Reverts once locked; rejects empty values (improvement over archive).
    /// @dev Emits `SymbolUpdated` with old and new values so indexers can track the rename.
    function setSymbol(string memory _symbol) public onlyOwner {
        require(!locked, "FlexibleToken: locked");
        require(bytes(_symbol).length > 0, "Empty symbol");
        emit SymbolUpdated(symbol, _symbol);
        symbol = _symbol;
    }

    /// @notice Replaces the full name. Reverts once locked; rejects empty values (improvement over archive).
    /// @dev Emits `NameUpdated` with old and new values so indexers can track the rename.
    function setName(string memory _name) public onlyOwner {
        require(!locked, "FlexibleToken: locked");
        require(bytes(_name).length > 0, "Empty name");
        emit NameUpdated(name, _name);
        name = _name;
    }

    /// @notice Returns circulating supply, treating zero-address holdings as burned.
    function totalSupply() public view returns (uint256) {
        return _totalSupply.sub(balances[address(0)]);
    }

    /// @notice Returns the token balance of `tokenOwner`.
    function balanceOf(address tokenOwner) public view returns (uint256) {
        return balances[tokenOwner];
    }

    /// @notice Moves `tokens` from caller to `to`. Reverts on insufficient balance or zero recipient.
    function transfer(address to, uint256 tokens) public returns (bool) {
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
    function approve(address spender, uint256 tokens) public returns (bool) {
        require(spender != address(0), "ERC20: approve to zero address");

        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    /// @notice Moves `tokens` from `from` to `to`, spending caller's allowance. Reverts if over balance/allowance.
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public returns (bool) {
        require(to != address(0), "ERC20: transfer to zero address");

        balances[from] = balances[from].sub(tokens);
        allowed[from][msg.sender] = allowed[from][msg.sender].sub(tokens);
        balances[to] = balances[to].add(tokens);

        emit Transfer(from, to, tokens);
        return true;
    }

    /// @notice Returns remaining tokens `spender` may pull from `tokenOwner`.
    function allowance(
        address tokenOwner,
        address spender
    ) public view returns (uint256) {
        return allowed[tokenOwner][spender];
    }

    /// @notice Approves `spender` then calls its `receiveApproval` in one transaction (MiniMe pattern).
    /// @dev TRUST WARNING (unchanged from archive): hands control to untrusted `spender` code,
    ///      which can re-enter before returning. Only use with vetted spender contracts.
    /// @param data Opaque payload forwarded to the spender.
    function approveAndCall(
        address spender,
        uint256 tokens,
        bytes memory data
    ) public returns (bool) {
        require(spender != address(0), "ERC20: zero spender");

        allowed[msg.sender][spender] = tokens;
        emit Approval(msg.sender, spender, tokens);

        ApproveAndCallFallBack(spender).receiveApproval(
            msg.sender,
            tokens,
            address(this),
            data
        );

        return true;
    }

    /// @notice Rejects all plain ETH transfers to this contract.
    function() external payable {
        revert();
    }

    /// @notice Owner-only rescue: pulls ERC-20 tokens accidentally sent to this contract out to `owner`.
    /// @dev Return value of the external call is propagated, not `require`d (unchanged from archive).
    function transferAnyERC20Token(
        address tokenAddress,
        uint256 tokens
    ) public onlyOwner returns (bool) {
        require(tokenAddress != address(0), "Invalid token address");
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}
