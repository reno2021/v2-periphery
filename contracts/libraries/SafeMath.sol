// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.5.0;

library SafeMath {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, 'SafeMath: addition overflow');
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, 'SafeMath: subtraction overflow');
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        if (x == 0) {
            return 0;
        }
        require((z = x * y) / x == y, 'SafeMath: multiplication overflow');
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y > 0, 'SafeMath: division by zero');
        z = x / y;
    }
}
