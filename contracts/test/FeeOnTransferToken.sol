// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import './ERC20TestToken.sol';

contract FeeOnTransferToken is ERC20TestToken {
    uint256 public immutable feeBps;
    address public immutable treasury;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply,
        uint256 feeBps_,
        address treasury_
    ) public ERC20TestToken(name_, symbol_, supply) {
        feeBps = feeBps_;
        treasury = treasury_;
    }

    function _transfer(address from, address to, uint256 value) internal override {
        uint256 fee = value.mul(feeBps) / 10000;
        uint256 net = value.sub(fee);
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(net);
        emit Transfer(from, to, net);
        if (fee > 0) {
            balanceOf[treasury] = balanceOf[treasury].add(fee);
            emit Transfer(from, treasury, fee);
        }
    }
}
