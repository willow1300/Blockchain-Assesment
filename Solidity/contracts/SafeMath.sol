// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SafeMath
 * @notice Arithmetic operations with overflow / underflow checks.
 * @dev Compatibility shim for contracts written in the SafeMath style.
 *
 *      Solidity 0.8.x already reverts on overflow, underflow and division
 *      by zero (Panic 0x11 / 0x12), so this library is NOT needed for safety.
 *      It is kept so 0.4.x / 0.5.x style code (`a.add(b)`, `a.sub(b)`, ...)
 *      keeps compiling with the same revert strings while you migrate.
 *
 *      Differences vs `archive/SafeMath.sol` (BokkyPooBah, 0.4.18):
 *        - `public` -> `internal`: functions inline at compile time, no
 *          external library linking / DELEGATECALL, cheaper deployment + calls.
 *        - `uint` -> explicit `uint256` everywhere.
 *        - Revert reasons added (`"SafeMath: ..."`), so failures are
 *          debuggable instead of bare `require(false)`.
 *        - `mul` short-circuits `if (a == 0) return 0`, skipping one `mul`
 *          and one `div` check (gas saving on zero multiplies).
 *        - `add` / `mul` use `unchecked { ... }` + manual `require` so the
 *          custom message is actually shown. Without `unchecked`, the 0.8
 *          built-in Panic would fire BEFORE the `require` is reached and the
 *          custom string would be dead code. `sub` / `div` check BEFORE the
 *          operation, so their messages work with or without `unchecked`.
 *        - `mod` added for completeness (parity with OpenZeppelin).
 *
 *      IMPORTANT VERSION NOTE:
 *        This file is `pragma ^0.8.20` and CANNOT be `import`ed by the
 *        `pragma ^0.5.17` tokens in this folder in the same compilation.
 *        Those tokens each carry their own embedded 0.5.x SafeMath.
 *        Use THIS file only for new 0.8.x contracts. When the tokens are
 *        migrated to 0.8.x, delete the embedded copies and
 *        `import "./SafeMath.sol"` (or better: drop SafeMath entirely and
 *        use plain `+ - * / %`, which are already checked).
 *
 *      FUTURE (gas) NOTE:
 *        `require` strings cost deployment gas. For a production 0.8.x
 *        codebase prefer custom errors
 *        (`error SafeMathAdditionOverflow();`) or plain operators.
 */
library SafeMath {
    /**
     * @notice Adds two numbers, reverting on overflow.
     * @dev Uses `unchecked` + manual check so the custom message is preserved.
     * @param a First operand.
     * @param b Second operand.
     * @return c Sum of `a` and `b`.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        unchecked {
            c = a + b;
            require(c >= a, "SafeMath: addition overflow");
        }
    }

    /**
     * @notice Subtracts two numbers, reverting on underflow.
     * @dev Check comes before the subtraction, so the message is shown.
     * @param a Minuend.
     * @param b Subtrahend (must be <= `a`).
     * @return c Difference `a - b`.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b <= a, "SafeMath: subtraction overflow");
        unchecked {
            c = a - b;
        }
    }

    /**
     * @notice Multiplies two numbers, reverting on overflow.
     * @dev Zero short-circuit saves gas; `unchecked` + manual check preserves
     *      the custom message (otherwise 0.8 Panic 0x11 pre-empts it).
     * @param a First factor.
     * @param b Second factor.
     * @return c Product `a * b`.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        unchecked {
            c = a * b;
            require(c / a == b, "SafeMath: multiplication overflow");
        }
    }

    /**
     * @notice Divides two numbers, reverting on division by zero.
     * @dev Check comes before the division, so the message is shown.
     * @param a Dividend.
     * @param b Divisor (must be > 0).
     * @return c Quotient `a / b` (integer division, truncates).
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "SafeMath: division by zero");
        unchecked {
            c = a / b;
        }
    }

    /**
     * @notice Modulo of two numbers, reverting on division by zero.
     * @dev Added for parity with OpenZeppelin-style SafeMath; the archive
     *      version had no `mod`.
     * @param a Dividend.
     * @param b Divisor (must be > 0).
     * @return c Remainder `a % b`.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b > 0, "SafeMath: modulo by zero");
        unchecked {
            c = a % b;
        }
    }
}
