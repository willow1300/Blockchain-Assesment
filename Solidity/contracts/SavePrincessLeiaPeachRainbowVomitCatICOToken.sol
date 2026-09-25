// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Save Princess Leia Peach Rainbow Vomit Cat ICO Token (LEIA)
 * @notice ERC20 token with 4-week ICO, 20% bonus week 1.
 * @dev Port of archive 0.4.18 to 0.8.20. Fixes: real constructor,
 * emit everywhere, now->block.timestamp, SafeMath mul, zero guards,
 * receive() with checks, and CRITICAL archive line 257 refund bug
 * (msg.sender.transfer refunded buyer => free tokens, zero raise).
 * Fixed: ETH retained, owner pulls via withdrawETH().
 * Limits kept: uncapped, no per-wallet cap, no refunds, timestamp drift,
 * approve race, untrusted approveAndCall.
 */
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

/** @title Owned - two-step transfer, gates withdraw + rescue only. */
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
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        unchecked { c = a + b; require(c >= a, "SafeMath: addition overflow"); }
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a, "SafeMath: subtraction overflow");
        unchecked { c = a - b; }
    }
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) { return 0; }
        unchecked { c = a * b; require(c / a == b, "SafeMath: multiplication overflow"); }
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "SafeMath: division by zero");
        unchecked { c = a / b; }
    }
}

contract SavePrincessLeiaPeachRainbowVomitCatICOToken is ERC20Interface, Owned {
    using SafeMath for uint256;
    string public symbol;
    string public name;
    uint8 public decimals;
    uint256 public _totalSupply;
    uint256 public startDate;
    uint256 public bonusEnds;
    uint256 public endDate;
    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowed;
    event ICOContribution(address indexed c, uint256 weiAmt, uint256 tokAmt);
    event ETHWithdrawn(address indexed to, uint256 amount);
    constructor() {
        symbol = "LEIA";
        name = "Save Princess Leia Peach Rainbow Vomit Cat ICO Token";
        decimals = 18;
        startDate = block.timestamp;
        bonusEnds = block.timestamp + 1 weeks;
        endDate = block.timestamp + 4 weeks;
    }
    function totalSupply() public view override returns (uint256) {
        return _totalSupply.sub(balances[address(0)]);
    }
    function balanceOf(address o) public view override returns (uint256) {
        return balances[o];
    }
    function transfer(address to, uint256 t) public override returns (bool) {
        require(to != address(0), "Invalid recipient");
        balances[msg.sender] = balances[msg.sender].sub(t);
        balances[to] = balances[to].add(t);
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
        balances[f] = balances[f].sub(v);
        allowed[f][msg.sender] = allowed[f][msg.sender].sub(v);
        balances[t] = balances[t].add(v);
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
    receive() external payable {
        require(block.timestamp >= startDate && block.timestamp <= endDate, "ICO is not active");
        require(msg.value > 0, "ETH required");
        uint256 tokens;
        if (block.timestamp <= bonusEnds) { tokens = msg.value.mul(1200); }
        else { tokens = msg.value.mul(1000); }
        balances[msg.sender] = balances[msg.sender].add(tokens);
        _totalSupply = _totalSupply.add(tokens);
        emit Transfer(address(0), msg.sender, tokens);
        emit ICOContribution(msg.sender, msg.value, tokens);
    }
    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient ETH balance");
        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "ETH withdraw failed");
        emit ETHWithdrawn(owner, amount);
    }
    function transferAnyERC20Token(address tok, uint256 t) external onlyOwner returns (bool) {
        require(tok != address(0), "Invalid token address");
        bool ok = ERC20Interface(tok).transfer(owner, t);
        require(ok, "Rescue transfer failed");
        return true;
    }
}
