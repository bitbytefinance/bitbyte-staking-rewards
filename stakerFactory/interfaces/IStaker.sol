
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStaker {
    function initialize(
        address _creator,
        address _stakingToken,
        address _rewardsToken,
        address _rlink,
        uint _incentiveRate,
        uint _parentRate,
        uint _grandpaRate
    ) external;

    function factory() external view returns(address);

    function getStakingToken() external view returns(address);

    function getRewardsToken() external view returns(address);

    function createTime() external view returns(uint256);
    
    function creator() external view returns(address);

    function rewardRate() external view returns(uint256);

    function periodFinish() external view returns(uint256);

    function totalSupply() external view returns(uint);

    function balanceOf(address account) external view returns(uint);

    function earned(address account) external view returns(uint);

    function availableReserve() external view returns(uint256);

    function notifyRewardAmount(uint256 _reward,uint256 _rewardsDuration) external;

    /* ========== EVENTS ========== */

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardReserveAdded(address indexed sender,uint256 rewardAmount);
    event RewardAdded(address sender, uint256 reward);
    event DistributeAgentChanged(address indexed sender,address oldAgent,address newAgent);
    event RefRatesChanged(address indexed sender,uint256 incentiveRate,uint256 parentRate,uint256 grandpaRate);
    event TakedToken(address indexed token,address indexed to, uint256 amount);
    event LockExpireChanged(uint oldExpire,uint newExpire);
}