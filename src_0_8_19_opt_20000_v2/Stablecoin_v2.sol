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

import {Account} from "./type/Account.sol";
import {Chain} from "./type/Chain.sol";
import {Count} from "./type/Count.sol";
import {Duration} from "./type/Duration.sol";
import {OpIndex} from "./type/OpIndex.sol";
import {PoolIndex} from "./type/PoolIndex.sol";
import {MintOperations} from "./library/MintOperation.sol";
import {MintOperationArrays} from "./library/MintOperationArray.sol";
import {MintPools} from "./library/MintPool.sol";
import {MintPoolArrays} from "./library/MintPoolArray.sol";
import {ProofOfReserve} from "./library/ProofOfReserve.sol";
import {Redemption} from "./library/Redemption.sol";
import {Bridging} from "./library/Bridging.sol";

contract Stablecoin_v2 is AccessControlEnumerableUpgradeable, UUPSUpgradeable, PausableUpgradeable, ERC20Upgradeable {
    using MintOperations for MintOperations.Op;
    using MintOperationArrays for MintOperationArrays.Array;
    using MintPools for MintPools.Pool;
    using MintPoolArrays for MintPoolArrays.Array;
    using ProofOfReserve for ProofOfReserve.Params;
    using Redemption for Redemption.Params;
    using Bridging for Bridging.Params;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant MINT_RATIFIER_ROLE = keccak256("MINT_RATIFIER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FROZEN_ROLE = keccak256("FROZEN_ROLE");
    bytes32 public constant ACCOUNT_ADMIN_ROLE = keccak256("ACCOUNT_ADMIN_ROLE");

    uint256 public constant CENT = 10 ** 16;

    // Users redeem and bridge by sending ordinary ERC20 transfers to
    // designated Sentinel addresses. We assume that it is infeasible to either
    // create a smart contract or find an EOA private key for Sentinel
    // addresses.
    //
    // WARNING: To keep a 128-bit security level against Sentinel collisions,
    // we've left at least 32 hex 0s in all Sentinel addresses.
    //
    // Since addresses have 40 hex chars total, this allows us to use:
    // - 2 hex chars to specify a Chain, and
    // - 6 hex chars to specify an Account
    //
    // NOTE: Solidity treats any 39-41 hex char uint as an address literal,
    // and enforces EIP-55 mixed-case checksumming. To avoid mixed-case, we
    // prepend 0x00_ to these constants to make them 42 hex chars.
    uint160 public constant CHAIN_BITMASK = 0x00_ff00000000000000000000000000000000000000;
    uint160 public constant SENTINEL_BITMASK = 0x00_00ffffffffffffffffffffffffffffffff000000;
    uint160 public constant ACCOUNT_BITMASK = 0x00_0000000000000000000000000000000000ffffff;
    uint8 public constant CHAIN_BITSHIFT = 38 * 4; // hex chars * bits per hex char

    // Chain 0x00 represents a redemption. Any other Chain represents a bridge.
    Chain public constant ZERO_CHAIN = Chain.wrap(0x00);
    // Account 0x000000 interferes with ERC20 address(0) burns, and is hence
    // disallowed for bridging + redemption.
    Account public constant ZERO_ACCOUNT = Account.wrap(0x000000);

    MintOperationArrays.Array private _mintOperations;
    MintPoolArrays.Array private _mintPools;
    ProofOfReserve.Params private _proofOfReserveParams;
    Redemption.Params private _redemptionParams;
    Bridging.Params private _bridgingParams;

    event PushMintPool(PoolIndex poolIndex, Count signatures, uint256 threshold, uint256 limit);
    event PopMintPool(PoolIndex poolIndex);

    event SetMintSignatures(PoolIndex poolIndex, Count signatures);
    event SetMintThreshold(PoolIndex poolIndex, uint256 threshold);
    event SetMintLimit(PoolIndex poolIndex, uint256 limit);

    event EnableProofOfReserve();
    event DisableProofOfReserve();
    event SetProofOfReserveFeed(AggregatorV3Interface feed);
    event SetProofOfReserveHeartbeat(Duration heartbeat);

    event SetRedemptionMin(uint256 min);
    event AllowAccountRedemption(Account account);
    event ForbidAccountRedemption(Account account);

    event SetBridgingMin(uint256 min);
    event AllowBridgingChain(Chain chain);
    event ForbidBridgingChain(Chain chain);
    event AllowAccountBridging(Account account);
    event ForbidAccountBridging(Account account);

    event ApproveRefillMintPool(PoolIndex poolIndex, address approver);
    event FinalizeRefillMintPool(PoolIndex poolIndex);

    event RequestMint(OpIndex opIndex, address to, uint256 value, address requester);
    event RatifyMint(OpIndex opIndex, address ratifier);
    event FinalizeMint(OpIndex opIndex, PoolIndex poolIndex);
    event RevokeMint(OpIndex opIndex, address revoker);

    event Redeem(Account account, uint256 amount);
    event Bridge(Chain chain, Account account, uint256 amount);

    event Burn(address from, uint256 amount);
    event ReclaimEther(address admin, uint256 amount);
    event ReclaimToken(IERC20Upgradeable token, address admin, uint256 amount);

    error AddressHasFrozenRole(address address_);
    error MintToAddressZero(address to);
    error MintToSentinelAddress(address to);
    error AmountDoesNotHaveExactCent(uint256 amount);
    error AllowRedemptionToZeroAccount();
    error AllowBridgingToZeroChain();
    error AllowBridgingToZeroAccount();

    constructor() {
        _disableInitializers();
    }

    function initializeV2() public reinitializer(2) {
        bytes32 redemptionAddressRole = keccak256("REDEMPTION_ADDRESS_ROLE");
        _setRoleAdmin(redemptionAddressRole, DEFAULT_ADMIN_ROLE);
        grantRole(ACCOUNT_ADMIN_ROLE, address(this));
        while (getRoleMemberCount(redemptionAddressRole) > 0) {
            address redemptionAddress = getRoleMember(redemptionAddressRole, 0);
            revokeRole(redemptionAddressRole, redemptionAddress);
            this.allowAccountRedemption(_account(redemptionAddress));
        }
        revokeRole(ACCOUNT_ADMIN_ROLE, address(this));

        bytes32 redemptionAdminRole = keccak256("REDEMPTION_ADMIN_ROLE");
        while (getRoleMemberCount(redemptionAdminRole) > 0) {
            address redemptionAdmin = getRoleMember(redemptionAdminRole, 0);
            revokeRole(redemptionAdminRole, redemptionAdmin);
            grantRole(ACCOUNT_ADMIN_ROLE, redemptionAdmin);
        }
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
            revert AddressHasFrozenRole(from);
        }
        if (hasRole(FROZEN_ROLE, to)) {
            revert AddressHasFrozenRole(to);
        }
    }

    function _afterTokenTransfer(address, address to, uint256 amount) internal virtual override {
        if (to == address(0) || !_isSentinel(to)) {
            return;
        }
        if (amount % CENT != 0) {
            revert AmountDoesNotHaveExactCent(amount);
        }

        Chain chain = _chain(to);
        Account account = _account(to);
        if (chain == ZERO_CHAIN) {
            _redemptionParams.checkRedemption(account, amount);
            emit Redeem(account, amount);
        } else {
            _bridgingParams.checkBridging(chain, account, amount);
            emit Bridge(chain, account, amount);
        }

        _burn(to, amount);
    }

    function _chain(address address_) private pure returns (Chain) {
        return Chain.wrap(uint8((uint160(address_) & CHAIN_BITMASK) >> CHAIN_BITSHIFT));
    }

    function _isSentinel(address address_) private pure returns (bool) {
        return uint160(address_) & SENTINEL_BITMASK == 0;
    }

    function _account(address address_) private pure returns (Account) {
        return Account.wrap(uint24(uint160(address_)));
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

    function viewProofOfReserve() external view returns (bool, uint8, AggregatorV3Interface, Duration) {
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

    function viewRedemptionAccountsCount() external view returns (uint256) {
        return _redemptionParams.accountsLength();
    }

    function viewRedemptionAccountAt(uint256 index) external view returns (Account) {
        return _redemptionParams.accountAt(index);
    }

    function canAccountRedeem(Account account) external view returns (bool) {
        return _redemptionParams.canAccountRedeem(account);
    }

    function viewMinimumBridgingAmount() external view returns (uint256) {
        return _bridgingParams.min();
    }

    function viewBridgingChainsCount() external view returns (uint256) {
        return _bridgingParams.chainsLength();
    }

    function viewBridgingChainAt(uint256 index) external view returns (Chain) {
        return _bridgingParams.chainAt(index);
    }

    function canBridgeToChain(Chain chain) external view returns (bool) {
        return _bridgingParams.canBridgeToChain(chain);
    }

    function viewBridgingAccountsCount() external view returns (uint256) {
        return _bridgingParams.accountsLength();
    }

    function viewBridgingAccountAt(uint256 index) external view returns (Account) {
        return _bridgingParams.accountAt(index);
    }

    function canAccountBridge(Account account) external view returns (bool) {
        return _bridgingParams.canAccountBridge(account);
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

    function setProofOfReserveHeartbeat(Duration heartbeat) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _proofOfReserveParams.setHeartbeat(heartbeat);
        emit SetProofOfReserveHeartbeat(heartbeat);
    }

    function setRedemptionMin(uint256 min) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _redemptionParams.setMin(min);
        emit SetRedemptionMin(min);
    }

    function allowAccountRedemption(Account account) external onlyRole(ACCOUNT_ADMIN_ROLE) {
        if (account == ZERO_ACCOUNT) {
            revert AllowRedemptionToZeroAccount();
        }
        if (_redemptionParams.allowAccount(account)) {
            emit AllowAccountRedemption(account);
        }
    }

    function forbidAccountRedemption(Account account) external onlyRole(ACCOUNT_ADMIN_ROLE) {
        if (_redemptionParams.forbidAccount(account)) {
            emit ForbidAccountRedemption(account);
        }
    }

    function setBridgingMin(uint256 min) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _bridgingParams.setMin(min);
        emit SetBridgingMin(min);
    }

    function allowBridgingChain(Chain chain) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (chain == ZERO_CHAIN) {
            revert AllowBridgingToZeroChain();
        }
        if (_bridgingParams.allowChain(chain)) {
            emit AllowBridgingChain(chain);
        }
    }

    function forbidBridgingChain(Chain chain) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_bridgingParams.forbidChain(chain)) {
            emit ForbidBridgingChain(chain);
        }
    }

    function allowAccountBridging(Account account) external onlyRole(ACCOUNT_ADMIN_ROLE) {
        if (account == ZERO_ACCOUNT) {
            revert AllowBridgingToZeroAccount();
        }
        if (_bridgingParams.allowAccount(account)) {
            emit AllowAccountBridging(account);
        }
    }

    function forbidAccountBridging(Account account) external onlyRole(ACCOUNT_ADMIN_ROLE) {
        if (_bridgingParams.forbidAccount(account)) {
            emit ForbidAccountBridging(account);
        }
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
        if (to == address(0)) {
            revert MintToAddressZero(to);
        }
        if (_isSentinel(to)) {
            revert MintToSentinelAddress(to);
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
