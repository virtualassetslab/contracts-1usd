// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "chainlink-v2.7.2/src/v0.8/interfaces/AggregatorV3Interface.sol";
// solhint-disable-next-line max-line-length
import {AccessControlEnumerableUpgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/access/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/proxy/utils/UUPSUpgradeable.sol";
// solhint-disable-next-line max-line-length
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/security/PausableUpgradeable.sol";
import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20Upgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/token/ERC20/IERC20Upgradeable.sol";
// solhint-disable-next-line max-line-length
import {SafeERC20Upgradeable} from "openzeppelin-contracts-upgradeable-v4.9.5/contracts/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {Count} from "./library/ApprovalSet.sol";
import {MintOperations} from "./library/MintOperation.sol";
import {MintOperationArrays, OpIndices, OpIndex} from "./library/MintOperationArray.sol";
import {MintPools} from "./library/MintPool.sol";
import {MintPoolArrays, PoolIndices, PoolIndex} from "./library/MintPoolArray.sol";
import {ProofOfReserve} from "./library/ProofOfReserve.sol";
import {Redemption} from "./library/Redemption.sol";

contract Stablecoin is AccessControlEnumerableUpgradeable, UUPSUpgradeable, PausableUpgradeable, ERC20Upgradeable {
    using MintOperations for MintOperations.Op;
    using MintOperationArrays for MintOperationArrays.Array;
    using OpIndices for OpIndex;
    using MintPools for MintPools.Pool;
    using MintPoolArrays for MintPoolArrays.Array;
    using PoolIndices for PoolIndex;
    using ProofOfReserve for ProofOfReserve.Params;
    using Redemption for Redemption.Params;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MINT_RATIFIER_ROLE = keccak256("MINT_RATIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FROZEN_ROLE = keccak256("FROZEN_ROLE");
    bytes32 public constant REDEMPTION_ADMIN_ROLE = keccak256("REDEMPTION_ADMIN_ROLE");
    bytes32 public constant REDEMPTION_ADDRESS_ROLE = keccak256("REDEMPTION_ADDRESS_ROLE");

    uint256 public constant CENT = 10 ** 16;
    address public constant MAX_REDEMPTION_ADDRESS = address(0x100000);

    MintOperationArrays.Array private _mintOperations;
    MintPoolArrays.Array private _mintPools;
    ProofOfReserve.Params private _proofOfReserveParams;
    Redemption.Params private _redemptionParams;

    event PushMintPool(PoolIndex poolIndex, Count signatures, uint256 threshold, uint256 limit);
    event PopMintPool(PoolIndex poolIndex);

    event SetMintSignatures(PoolIndex poolIndex, Count signatures);
    event SetMintThreshold(PoolIndex poolIndex, uint256 threshold);
    event SetMintLimit(PoolIndex poolIndex, uint256 limit);

    event EnableProofOfReserve();
    event DisableProofOfReserve();
    event SetProofOfReserveFeed(AggregatorV3Interface feed);
    event SetProofOfReserveHeartbeat(uint256 heartbeat);

    event SetRedemptionMin(uint256 min);

    event ApproveRefillMintPool(PoolIndex poolIndex, address approver);
    event FinalizeRefillMintPool(PoolIndex poolIndex);

    event RequestMint(OpIndex opIndex, address to, uint256 value, address requester);
    event RatifyMint(OpIndex opIndex, address ratifier);
    event FinalizeMint(OpIndex opIndex, PoolIndex poolIndex);
    event RevokeMint(OpIndex opIndex, address revoker);

    event Redeem(address redemptionAddress, uint256 amount);

    event Burn(address from, uint256 amount);
    event ReclaimEther(address admin, uint256 amount);
    event ReclaimToken(IERC20Upgradeable token, address admin, uint256 amount);

    error AccountHasFrozenRole(address account);
    error MintToAddressZeroOrRedemptionAddress(address to);
    error AmountDoesNotHaveExactCent(uint256 amount);

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory name_, string memory symbol_) public initializer {
        AccessControlEnumerableUpgradeable.__AccessControlEnumerable_init();
        ERC20Upgradeable.__ERC20_init(name_, symbol_);
        UUPSUpgradeable.__UUPSUpgradeable_init();
        PausableUpgradeable.__Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setRoleAdmin(REDEMPTION_ADDRESS_ROLE, REDEMPTION_ADMIN_ROLE);
        _proofOfReserveParams.setDecimals(decimals());
        assert(CENT == 10 ** (decimals() - 2));
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256) internal view virtual override {
        if (hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            return;
        }
        _requireNotPaused();
        if (hasRole(FROZEN_ROLE, from)) {
            revert AccountHasFrozenRole(from);
        }
        if (hasRole(FROZEN_ROLE, to)) {
            revert AccountHasFrozenRole(to);
        }
    }

    function _afterTokenTransfer(address, address to, uint256 amount) internal virtual override {
        if (to != address(0) && uint160(to) <= uint160(MAX_REDEMPTION_ADDRESS)) {
            _checkRole(REDEMPTION_ADDRESS_ROLE, to);
            if (amount % CENT != 0) {
                revert AmountDoesNotHaveExactCent(amount);
            }
            _redemptionParams.checkRedemption(amount);

            _burn(to, amount);
            emit Redeem(to, amount);
        }
    }

    function _isMintRatifier(address address_) private view returns (bool) {
        return hasRole(MINT_RATIFIER_ROLE, address_);
    }

    function _isUnfiltered(address) private pure returns (bool) {
        return true;
    }

    function viewMintPoolsCount() external view returns (PoolIndex) {
        return _mintPools.length();
    }

    function viewMintPool(PoolIndex poolIndex) external view returns (Count, uint256, uint256, uint256, Count, Count) {
        MintPools.Pool storage pool = _mintPools.at(poolIndex);
        return (
            pool.signatures(),
            pool.threshold(),
            pool.limit(),
            pool.value(),
            pool.refillApprovalsCount(_isMintRatifier),
            pool.refillApprovalsCount(_isUnfiltered)
        );
    }

    function viewUnfilteredMintPoolRefillApproval(
        PoolIndex poolIndex,
        Count refillApprovalIndex
    ) external view returns (address) {
        return _mintPools.at(poolIndex).refillApprovalAtIndex(refillApprovalIndex);
    }

    function viewMintOperationsCount() external view returns (OpIndex) {
        return _mintOperations.length();
    }

    function viewMintOperation(
        OpIndex opIndex
    ) external view returns (MintOperations.Status, address, uint256, Count, Count) {
        MintOperations.Op storage operation = _mintOperations.at(opIndex);
        return (
            operation.status(),
            operation.to(),
            operation.value(),
            operation.ratifierApprovals(_isMintRatifier),
            operation.ratifierApprovals(_isUnfiltered)
        );
    }

    function viewUnfilteredMintOperationRatifierApproval(
        OpIndex opIndex,
        Count ratifierApprovalIndex
    ) external view returns (address) {
        return _mintOperations.at(opIndex).ratifierApprovalAtIndex(ratifierApprovalIndex);
    }

    function viewProofOfReserve() external view returns (bool, uint8, AggregatorV3Interface, uint256) {
        return (
            _proofOfReserveParams.enabled(),
            _proofOfReserveParams.decimals(),
            _proofOfReserveParams.feed(),
            _proofOfReserveParams.heartbeat()
        );
    }

    function viewMinimumRedemptionAmount() external view returns (uint256) {
        return _redemptionParams.min();
    }

    function pushMintPool(Count signatures, uint256 threshold, uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolIndex poolIndex = _mintPools.length();
        _mintPools.push();
        _mintPools.setSignatures(poolIndex, signatures);
        _mintPools.setThreshold(poolIndex, threshold);
        _mintPools.setLimit(poolIndex, limit);
        refillLastMintPoolFromAdmin();
        emit PushMintPool(poolIndex, signatures, threshold, limit);
    }

    function popMintPool() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mintPools.pop();
        emit PopMintPool(_mintPools.length());
    }

    function setMintSignatures(PoolIndex poolIndex, Count signatures) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mintPools.setSignatures(poolIndex, signatures);
        emit SetMintSignatures(poolIndex, signatures);
    }

    function setMintThreshold(PoolIndex poolIndex, uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mintPools.setThreshold(poolIndex, threshold);
        emit SetMintThreshold(poolIndex, threshold);
    }

    function setMintLimit(PoolIndex poolIndex, uint256 limit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mintPools.setLimit(poolIndex, limit);
        emit SetMintLimit(poolIndex, limit);
    }

    function enableProofOfReserve() external onlyRole(PAUSER_ROLE) {
        _proofOfReserveParams.setEnabled(true);
        emit EnableProofOfReserve();
    }

    function disableProofOfReserve() external onlyRole(PAUSER_ROLE) {
        _proofOfReserveParams.setEnabled(false);
        emit DisableProofOfReserve();
    }

    function setProofOfReserveFeed(AggregatorV3Interface feed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _proofOfReserveParams.setFeed(feed);
        emit SetProofOfReserveFeed(feed);
    }

    function setProofOfReserveHeartbeat(uint256 heartbeat) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _proofOfReserveParams.setHeartbeat(heartbeat);
        emit SetProofOfReserveHeartbeat(heartbeat);
    }

    function setRedemptionMin(uint256 min) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _redemptionParams.setMin(min);
        emit SetRedemptionMin(min);
    }

    function approveRefillMintPoolFromNextPool(PoolIndex poolIndex) public onlyRole(MINT_RATIFIER_ROLE) {
        _mintPools.at(poolIndex).approveRefillFromPool(msg.sender);
        emit ApproveRefillMintPool(poolIndex, msg.sender);
    }

    function finalizeRefillMintPoolFromNextPool(PoolIndex poolIndex) public {
        _mintPools.at(poolIndex).finalizeRefillFromPool(_mintPools.at(poolIndex.next()), _isMintRatifier);
        emit FinalizeRefillMintPool(poolIndex);
    }

    function approveThenFinalizeRefillMintPoolFromNextPool(PoolIndex poolIndex) external {
        approveRefillMintPoolFromNextPool(poolIndex);
        finalizeRefillMintPoolFromNextPool(poolIndex);
    }

    function refillLastMintPoolFromAdmin() public onlyRole(DEFAULT_ADMIN_ROLE) {
        PoolIndex lastPoolIndex = _mintPools.length().prev();
        _mintPools.at(lastPoolIndex).refillFromAdmin();
        emit ApproveRefillMintPool(lastPoolIndex, msg.sender);
        emit FinalizeRefillMintPool(lastPoolIndex);
    }

    function requestMint(address to, uint256 value) public onlyRole(MINTER_ROLE) {
        if (uint160(to) <= uint160(MAX_REDEMPTION_ADDRESS)) {
            revert MintToAddressZeroOrRedemptionAddress(to);
        }
        if (value % CENT != 0) {
            revert AmountDoesNotHaveExactCent(value);
        }
        OpIndex opIndex = _mintOperations.length();
        _mintOperations.push().request(to, value);
        emit RequestMint(opIndex, to, value, msg.sender);
    }

    function ratifyMint(OpIndex opIndex) public onlyRole(MINT_RATIFIER_ROLE) {
        _mintOperations.at(opIndex).approve(msg.sender);
        emit RatifyMint(opIndex, msg.sender);
    }

    function finalizeMint(OpIndex opIndex, PoolIndex poolIndex) public {
        MintOperations.Op storage op = _mintOperations.at(opIndex);
        MintPools.Pool storage pool = _mintPools.at(poolIndex);
        uint256 value = op.value();

        _proofOfReserveParams.checkMint(value, totalSupply());

        op.finalize(pool.signatures(), _isMintRatifier);
        pool.spend(value);
        _mint(op.to(), value);
        emit FinalizeMint(opIndex, poolIndex);
    }

    function requestThenFinalizeMint(address to, uint256 value, PoolIndex poolIndex) external {
        OpIndex opIndex = _mintOperations.length();
        requestMint(to, value);
        finalizeMint(opIndex, poolIndex);
    }

    function ratifyThenFinalizeMint(OpIndex opIndex, PoolIndex poolIndex) external {
        ratifyMint(opIndex);
        finalizeMint(opIndex, poolIndex);
    }

    function revokeMint(OpIndex opIndex) external onlyRole(MINT_RATIFIER_ROLE) {
        _mintOperations.at(opIndex).revoke();
        emit RevokeMint(opIndex, msg.sender);
    }

    function burn(address account, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount % CENT != 0) {
            revert AmountDoesNotHaveExactCent(amount);
        }
        _burn(account, amount);
        emit Burn(account, amount);
    }

    function reclaimEther() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
        emit ReclaimEther(msg.sender, balance);
    }

    function reclaimToken(IERC20Upgradeable token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        SafeERC20Upgradeable.safeTransfer(token, msg.sender, balance);
        emit ReclaimToken(token, msg.sender, balance);
    }
}
