// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import '../interfaces/IERC20.sol';
import '../libraries/SafeMath.sol';

contract ERC20TestToken is IERC20 {
    using SafeMath for uint256;

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory name_, string memory symbol_, uint256 supply) public {
        name = name_;
        symbol = symbol_;
        _mint(msg.sender, supply);
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external virtual override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external virtual override returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != uint256(-1)) {
            allowance[from][msg.sender] = allowed.sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    function mint(address to, uint256 value) external {
        _mint(to, value);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    function _transfer(address from, address to, uint256 value) internal virtual {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }
}
