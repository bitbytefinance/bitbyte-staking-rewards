
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IStakerFactory {    
    function getStakerCreator(address staker) external view returns(address);
}