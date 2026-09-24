// SPDX-License-Identifier: MIT
pragma solidity ^0.5.17;

/// @title MyToken (MYT) — documented update of the archived BokkyPooBah example.
/// @notice ERC-20 minted by contributions: pay ETH to the fallback, receive MYT at 1000/wei (1200 in week 1).
/// @dev Pinned to solc 0.5.17 (last 0.5.x). A future upgrade should target ^0.8.x + OpenZeppelin
///      with the sale split into a separate crowdsale contract (cap, refunds, pull payments).

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
        if (a == 0) {
            return 0;
        }
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
    function receiveApproval(
        address from,
        uint256 tokens,
        address token,
        bytes memory data
    ) public;
}

/// @title Owned — two-step ownership transfer.
/// @notice `transferOwnership` nominates; `acceptOwnership` completes. Prevents locking by typo.
/// @dev Ownership here also means treasury rights: contributions forward ETH to `owner`.
contract Owned {
    address public owner;
    address public newOwner;

    /// @notice Emitted when ownership moves from one account to another.
    event OwnershipTransferred(address indexed _from, address indexed _to);

    /// @dev Deployer becomes the first owner — and therefore the first treasury.
    constructor() public {
        owner = msg.sender;
    }

    /// @notice Restricts a function to the current owner.
    modifier onlyOwner {
        require(msg.sender == owner, "Owned: caller is not the owner");
        _;
    }

    /// @notice Nominates a new owner. Does not take effect until accepted.
    /// @param _newOwner The nominee; zero address is rejected so ownership/treasury can't be burned by mistake.
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

/// @title MyToken — contribution-minted ERC-20 (MYT, 18 decimals).
/// @notice Sale window is fixed at deploy: start → +1 week bonus → +4 weeks close. No cap, no refunds.
/// @dev KNOWN LIMITS (faithful to archive, documented not fixed): uncapped supply, no per-wallet
///      limit, `block.timestamp` bonus edge manipulable ±seconds, ETH pushed to treasury on every
///      purchase (no escrow/pull pattern). A production sale should live in a separate contract.
contract MyToken is ERC20Interface, Owned {
    using SafeMath for uint256;

    string public symbol;
    string public name;
    uint8 public decimals;

    /// @dev Private; read via `totalSupply()`.
    uint256 private _totalSupply;
    /// @notice Contribution window start (deploy time).
    uint256 public startDate;
    /// @notice Bonus deadline: 1200/wei at or before this, 1000/wei after, until `endDate`.
    uint256 public bonusEnds;
    /// @notice Contribution window end (deploy + 4 weeks). Purchases revert after this.
    uint256 public endDate;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;

    /// @notice Emitted on every purchase: who paid, how much wei, how many tokens minted.
    event Contribution(address indexed contributor, uint256 weiAmount, uint256 tokenAmount);

    /// @notice Deploys MYT with zero supply and stamps the 4-week sale window from `block.timestamp`.
    /// @dev Improvement over archive: drops the pointless `balances[owner] = 0` + zero `Transfer` event.
    constructor() public {
        symbol = "MYT";
        name = "MyToken";
        decimals = 18;

        _totalSupply = 0;

        startDate = block.timestamp;
        bonusEnds = block.timestamp + 1 weeks;
        endDate = block.timestamp + 4 weeks;
    }

    /// @notice Returns circulating supply, treating zero-address holdings as burned.
    function totalSupply() public view returns (uint256) {
        return _totalSupply.sub(balances[address(0)]);
    }

    /// @notice Returns the token balance of `tokenOwner`.
    function balanceOf(address tokenOwner) public view returns (uint256 balance) {
        return balances[tokenOwner];
    }

    /// @notice Moves `tokens` from caller to `to`. Reverts on insufficient balance or zero recipient.
    function transfer(address to, uint256 tokens) public returns (bool success) {
        require(to != address(0), "MyToken: invalid recipient");

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
        require(spender != address(0), "MyToken: invalid spender");
        allowed[msg.sender][spender] = tokens;

        emit Approval(msg.sender, spender, tokens);
        return true;
    }

    /// @notice Moves `tokens` from `from` to `to`, spending caller's allowance. Reverts if over balance/allowance.
    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) public returns (bool success) {
        require(to != address(0), "MyToken: invalid recipient");

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
    ) public view returns (uint256 remaining) {
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
    ) public returns (bool success) {
        require(spender != address(0), "MyToken: invalid spender");
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

    /// @notice Buys MYT with ETH: 1200 tokens/wei during the bonus week, 1000 after, until `endDate`.
    /// @dev Effects (mint + events) happen BEFORE the treasury payout — checks-effects-interactions.
    ///      ETH is pushed to `owner` via low-level call (your fix): forwards all gas so payable-contract
    ///      treasuries work, unlike `transfer()`'s 2300-gas stipend. A failed payout reverts the purchase.
    ///      NO REFUNDS / NO CAP: failed windows revert, but successful buys are final and unlimited.
    function () external payable {
        require(
            block.timestamp >= startDate &&
            block.timestamp <= endDate,
            "MyToken: contribution window closed"
        );

        uint256 tokens;

        if (block.timestamp <= bonusEnds) {
            tokens = msg.value.mul(1200);
        } else {
            tokens = msg.value.mul(1000);
        }

        balances[msg.sender] = balances[msg.sender].add(tokens);
        _totalSupply = _totalSupply.add(tokens);

        emit Transfer(address(0), msg.sender, tokens);
        emit Contribution(msg.sender, msg.value, tokens);

        (bool sent, ) = address(uint160(owner)).call.value(msg.value)("");
        require(sent, "MyToken: treasury payment failed");
    }

    /// @notice Owner-only rescue: pulls ERC-20 tokens accidentally sent to this contract out to `owner`.
    /// @dev Zero-address token guard added. Return value is propagated, not `require`d (unchanged from archive).
    function transferAnyERC20Token(
        address tokenAddress,
        uint256 tokens
    ) public onlyOwner returns (bool success) {
        require(tokenAddress != address(0), "MyToken: invalid token address");
        return ERC20Interface(tokenAddress).transfer(owner, tokens);
    }
}

