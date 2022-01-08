// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.10;

import {Errors} from '../../libraries/helpers/Errors.sol';
import {VersionedInitializable} from '../../libraries/aave-upgradeability/VersionedInitializable.sol';
import {IPool} from '../../../interfaces/IPool.sol';
import {ICreditDelegationToken} from '../../../interfaces/ICreditDelegationToken.sol';
import {IERC20} from '../../../dependencies/openzeppelin/contracts/IERC20.sol';
import {EIP712Base} from './EIP712Base.sol';
import {Context} from '../../../dependencies/openzeppelin/contracts/Context.sol';

/**
 * @title DebtTokenBase
 * @author Aave
 * @notice Base contract for different types of debt tokens, like StableDebtToken or VariableDebtToken
 * @dev Transfer and approve functionalities are disabled since its a non-transferable token.
 */
abstract contract DebtTokenBase is
  VersionedInitializable,
  EIP712Base,
  Context,
  ICreditDelegationToken
{
  // Map of borrow allowances (delegator => delegatee => borrowAllowanceAmount)
  mapping(address => mapping(address => uint256)) internal _borrowAllowances;

  // Credit Delegation Typehash
  bytes32 public constant DELEGATION_WITH_SIG_TYPEHASH =
    keccak256('DelegationWithSig(address delegatee,uint256 value,uint256 nonce,uint256 deadline)');

  address internal _underlyingAsset;

  /**
   * @dev Constructor.
   */
  constructor() EIP712Base() {}

  /// @inheritdoc ICreditDelegationToken
  function approveDelegation(address delegatee, uint256 amount) external override {
    _approveDelegation(_msgSender(), delegatee, amount);
  }

  /**
   * @notice Implements the credit delegation with ERC712 signature
   * @param delegator The delegator of the credit
   * @param delegatee The delegatee that can use the credit
   * @param value The amount to be delegated
   * @param deadline The deadline timestamp, type(uint256).max for max deadline
   * @param v The V signature param
   * @param s The S signature param
   * @param r The R signature param
   */
  function delegationWithSig(
    address delegator,
    address delegatee,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external {
    require(delegator != address(0), Errors.ZERO_ADDRESS_NOT_VALID);
    //solium-disable-next-line
    require(block.timestamp <= deadline, Errors.INVALID_EXPIRATION);
    uint256 currentValidNonce = _nonces[delegator];
    bytes32 digest = keccak256(
      abi.encodePacked(
        '\x19\x01',
        DOMAIN_SEPARATOR(),
        keccak256(
          abi.encode(DELEGATION_WITH_SIG_TYPEHASH, delegatee, value, currentValidNonce, deadline)
        )
      )
    );
    require(delegator == ecrecover(digest, v, r, s), Errors.INVALID_SIGNATURE);
    _nonces[delegator] = currentValidNonce + 1;
    _approveDelegation(delegator, delegatee, value);
  }

  /// @inheritdoc ICreditDelegationToken
  function borrowAllowance(address fromUser, address toUser)
    external
    view
    override
    returns (uint256)
  {
    return _borrowAllowances[fromUser][toUser];
  }

  /**
   * @notice Updates the borrow allowance of a user on the specific debt token.
   * @param delegator The address delegating the borrowing power
   * @param delegatee The address receiving the delegated borrowing power
   * @param amount The allowance amount being delegated.
   **/
  function _approveDelegation(
    address delegator,
    address delegatee,
    uint256 amount
  ) internal {
    _borrowAllowances[delegator][delegatee] = amount;
    emit BorrowAllowanceDelegated(delegator, delegatee, _underlyingAsset, amount);
  }

  /**
   * @notice Decreases the borrow allowance of a user on the specific debt token.
   * @param delegator The address delegating the borrowing power
   * @param delegatee The address receiving the delegated borrowing power
   * @param amount The amount to subtract from the current allowance
   **/
  function _decreaseBorrowAllowance(
    address delegator,
    address delegatee,
    uint256 amount
  ) internal {
    uint256 newAllowance = _borrowAllowances[delegator][delegatee] - amount;

    _borrowAllowances[delegator][delegatee] = newAllowance;

    emit BorrowAllowanceDelegated(delegator, delegatee, _underlyingAsset, newAllowance);
  }
}
