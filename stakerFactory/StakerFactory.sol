// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import './Staker.sol';

interface ISwapPair {
    function factory() external view returns(address);
}

contract StakerFactory {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => address)) public stakers;
    mapping(address => StakerInfo) public stakerInfos;
    address[] public tokenStakers;
    address[] public lpStakers;

    address public immutable rlinkRelation;
    address public immutable swapFactory;

    struct StakerInfo {
        uint256 specialFeeRate;        
        bool isSpecialFee;
    }

    event StakerCreated(address indexed creator,address indexed stakingToken,address indexed rewardsToken,address staker);
    event CreatorChanged(address indexed oldCreator,address newCreator);

    constructor(
        address _rlinkRelation,
        address _swapFactory
    ){
        require(_rlinkRelation != address(0),"rlink relation can not be address 0");
        require(_swapFactory != address(0),"_swapFactory can not be address 0");

        rlinkRelation = _rlinkRelation;
        swapFactory = _swapFactory;
    }
    
    function stakersLength(bool isLpStaker) external view returns(uint){
        return isLpStaker ? lpStakers.length : tokenStakers.length;       
    }
    
    function getStaker(address stakingToken,address rewardsToken) external view returns(address,address) {
        address staker = stakers[stakingToken][rewardsToken];
        return (
            staker,
            IStaker(staker).creator()
        );
    }

    function getStakerByIndex(uint index,bool isLpStaker) public view returns(address,address) {
        require(isLpStaker && index < lpStakers.length || !isLpStaker && index < tokenStakers.length,"invalid index");
        address staker = isLpStaker ? lpStakers[index] : tokenStakers[index];
        return (
            staker,
            IStaker(staker).creator()
        );
    }
    
    function getStakerCreator(address staker) external view returns(address){
        return IStaker(staker).creator();
    }

    // stakerParams[0]: address stakingToken
    // stakerParams[1]: address rewardsToken
    // stakerParams[2]: uint256 incentiveRate
    // stakerParams[3]: uint256 parentRate
    // stakerParams[4]: uint256 grandpaRate
    // stakerParams[5]: bool isLpStaker
    function createStaker(bytes32[] memory stakerParams) external {
        address stakingToken = _bytes32ToAddress(stakerParams[0]); 
        address rewardsToken = _bytes32ToAddress(stakerParams[1]); 

        require(stakers[stakingToken][rewardsToken] == address(0),"staker already exists");
        require(uint(stakerParams[5]) == 0 || ISwapPair(stakingToken).factory() == swapFactory,"staking token is not lp token");

        bytes memory bytecode = type(Staker).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(stakingToken, rewardsToken));
        address staker;
        assembly {
            staker := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IStaker staker_ = IStaker(staker);
        staker_.initialize(
            msg.sender,
            stakingToken,
            rewardsToken,
            rlinkRelation,
            uint(stakerParams[2]),
            uint(stakerParams[3]),
            uint(stakerParams[4])
        );     

        stakers[stakingToken][rewardsToken] = staker;
        if(uint(stakerParams[5]) > 0){
            lpStakers.push(staker);
        }else{
            tokenStakers.push(staker);
        }

        emit StakerCreated(msg.sender, stakingToken, rewardsToken, staker);
    }

    function _bytes32ToAddress(bytes32 buffer) internal pure returns(address){
        uint ui = uint(buffer);
        require(ui <= type(uint160).max,"bytes32 overflow uint160");

        return address(uint160(ui));
    }
}