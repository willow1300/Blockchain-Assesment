// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Sean Test Token (SEANTest)
 * @notice Fixed 100k supply, 0 decimals, holder hardcoded (archive parity).
 * @dev Port of archive 0.4.18 to 0.8.20. Fixes: real constructor, emit,
 * zero guards, calldata, receive+fallback reject ETH. Keeps safe* naming
 * and INITIAL_HOLDER. See file end for limits.
 */
library SafeMath {
    function safeAdd(uint256 a, uint256 b) internal pure returns (uint256 c) {
        unchecked { c = a + b; require(c >= a, "SafeMath: addition overflow"); }
    }
    function safeSub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a, "SafeMath: subtraction overflow");
        unchecked { c = a - b; }
    }
    function safeMul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) { return 0; }
        unchecked { c = a * b; require(c / a == b, "SafeMath: multiplication overflow"); }
    }
    function safeDiv(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "SafeMath: division by zero");
        unchecked { c = a / b; }
    }
}

/** @notice ERC20 interface for token + rescue. */
interface ERC20Interface {
    function totalSupply() external view returns (uint256);
    function balanceOf(address o) external view returns (uint256);
    function allowance(address o, address s) external view returns (uint256);
    function transfer(address to, uint256 t) external returns (bool);
    function approve(address s, uint256 t) external returns (bool);
    function transferFrom(address f, address t, uint256 v) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 tokens);
    event Approval(address indexed o, address indexed s, uint256 tokens);
}

/** @notice Callback for approveAndCall. WARNING: spender untrusted. */
interface ApproveAndCallFallBack {
    function receiveApproval(address f, uint256 t, address tok, bytes calldata d) external;
}

/** @title Owned - two-step transfer, gates rescue only. */
contract Owned {
    address public owner;
    address public newOwner;
    event OwnershipTransferred(address indexed from, address indexed to);
    constructor() { owner = msg.sender; }
    modifier onlyOwner() { require(msg.sender == owner, "Not the owner"); _; }
    function transferOwnership(address n) external onlyOwner {
        require(n != address(0), "Invalid new owner"); newOwner = n;
    }
    function acceptOwnership() external {
        require(msg.sender == newOwner, "Not nominated owner");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner; newOwner = address(0);
    }
}

contract SeanTestToken is ERC20Interface, Owned {
    using SafeMath for uint256;
    string public symbol;
    string public name;
    uint8 public decimals;
    uint256 public _totalSupply;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;
    address public constant INITIAL_HOLDER = 0xB077883bF6154C9a24538A580Bd0d2F905D85384;
    constructor() {
        symbol = "SEANTest";
        name = "Sean Test";
        decimals = 0;
        _totalSupply = 100000;
        balances[INITIAL_HOLDER] = _totalSupply;
        emit Transfer(address(0), INITIAL_HOLDER, _totalSupply);
    }
    function totalSupply() public view override returns (uint256) {
        return _totalSupply.safeSub(balances[address(0)]);
    }
    function balanceOf(address o) public view override returns (uint256) {
        return balances[o];
    }
    function transfer(address to, uint256 t) public override returns (bool) {
        require(to != address(0), "Invalid recipient");
        balances[msg.sender] = balances[msg.sender].safeSub(t);
        balances[to] = balances[to].safeAdd(t);
        emit Transfer(msg.sender, to, t);
        return true;
    }
    function approve(address s, uint256 t) public override returns (bool) {
        require(s != address(0), "Invalid spender");
        allowed[msg.sender][s] = t;
        emit Approval(msg.sender, s, t);
        return true;
    }
    function transferFrom(address f, address t, uint256 v) public override returns (bool) {
        require(t != address(0), "Invalid recipient");
        balances[f] = balances[f].safeSub(v);
        allowed[f][msg.sender] = allowed[f][msg.sender].safeSub(v);
        balances[t] = balances[t].safeAdd(v);
        emit Transfer(f, t, v);
        return true;
    }
    function allowance(address o, address s) public view override returns (uint256) {
        return allowed[o][s];
    }
    function approveAndCall(address s, uint256 t, bytes calldata d) external returns (bool) {
        require(s != address(0), "Invalid spender");
        allowed[msg.sender][s] = t;
        emit Approval(msg.sender, s, t);
        ApproveAndCallFallBack(s).receiveApproval(msg.sender, t, address(this), d);
        return true;
    }
    receive() external payable { revert("ETH not accepted"); }
    fallback() external payable { revert("ETH not accepted"); }
    function transferAnyERC20Token(address tok, uint256 t) external onlyOwner returns (bool) {
        require(tok != address(0), "Invalid token address");
        bool ok = ERC20Interface(tok).transfer(owner, t);
        require(ok, "Rescue transfer failed");
        return true;
    }
}
