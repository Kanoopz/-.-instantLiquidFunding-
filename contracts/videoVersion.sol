// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

interface iMetapoolLiquidEtherStaking
{
    function depositETH(address _receiver) external payable returns(uint256);
    function transferFrom(address from, address to, uint256 amount) external returns(bool);
}

contract instantLiquidFunding 
{
    struct phaseOneFunderOrder
    {
        address funder;
        uint quantityFunded;
    }

    struct phaseTwoFunderOrder
    {
        address funder;
        uint fullQuantityFunded;
        uint apyRewards;
        uint finalQuantityFundedWoApy;
    }



    address metaPoolLiquidEtherStakingScAddr = 0x748c905130CC15b92B97084Fd1eEBc2d2419146f;

    /*
        1000 = 0.1 %
        RESULT * 10 = 1%

        AMOUNT / 1000 = 0.1% // RESULT * 97 = 9.7%
    */

    uint percentage = 1000; 

    address public proposer;
    string public proposalDescription;
    uint public daysOfFunding;
    uint public stakingApy;
    bool public fundingCompleted; //Checks if the phase one and two are completed.///
    bool public fullCompleted; //Checks if funding phases are completed and if the funders already claimed the APY that they donated.///

    uint public fundingPhaseOneTimeStamp;
    uint public fundingPhaseTwoTimeStamp;

    uint public actualPhase;
    bool public settedForPhaseTwo;

    


    uint public fundPhaseOneOrdersNextId = 1;
    uint fundPhaseOneFinalId;
    uint public fundPhaseTwoOrdersNextId = 1; 




    mapping (uint => phaseOneFunderOrder) public ordersPhaseOne;
    mapping (uint => phaseTwoFunderOrder) public ordersPhaseTwo;

    uint public phaseOneFundedEtherQuantity; //In wei.///

    mapping(address => uint) public quantityDeposited;
    mapping(uint => uint) public orderQuantityFulfilled;

    uint public actualOrderInFulfillment = 1;

    mapping (uint => bool) public orderPhaseOneFulfilled;






    constructor(address paramProposer, uint paramDaysOfFunding, uint paramStakingApy)
    {
        proposer = paramProposer;
        daysOfFunding = paramDaysOfFunding;
        stakingApy = paramStakingApy;

        fundingPhaseOneTimeStamp = block.timestamp;
        actualPhase = 1;
    }

    




    function fundPhaseOne() public payable
    {
        require(fullCompleted == false, "Proposal already ended.");
        require(fundingCompleted == false, "Proposal already ended.");
        require(actualPhase == 1, "phaseOne already over.");
        //require(checkDuration(1) > 0, "Time for phase already ended.");
        require(msg.value >= 0.003 ether, "Ether provided isnt enought for minimum funding.");


        address funder = msg.sender;
        uint quantityToFund = msg.value; //In wei.///

        phaseOneFunderOrder memory newPhaseOneOrder = phaseOneFunderOrder(funder, quantityToFund);
        ordersPhaseOne[fundPhaseOneOrdersNextId] = newPhaseOneOrder;
        fundPhaseOneOrdersNextId++;

        quantityDeposited[funder] = quantityToFund;
        phaseOneFundedEtherQuantity += quantityToFund;      
    }

    function prepareForPhaseTwo() public 
    {
        require(msg.sender == proposer, "Invalid; not proposer address.");
        require(address(this).balance == phaseOneFundedEtherQuantity, "Mismatch; problem with contract funding calcualtion.");

        iMetapoolLiquidEtherStaking(metaPoolLiquidEtherStakingScAddr).depositETH{value: address(this).balance}(address(this));

        fundPhaseOneFinalId = fundPhaseOneOrdersNextId - 1;

        actualPhase = 2;
        settedForPhaseTwo = true;
        fundingPhaseTwoTimeStamp = block.timestamp;
    }

    function fundPhaseTwo(uint paramFundingValue) public payable
    {
        require(fullCompleted == false, "Proposal already ended.");
        require(msg.value >= 3000000000000000, "Ether provided isnt enought for minimum funding.");

        require(actualPhase == 2, "Not in phaseTwo yet.");
        require(settedForPhaseTwo, "phaseTwo hasnt been setted.");
        //require(fundingPhaseTwoTimeStamp != 0, "fundingPhaseTwo not setted correctly.");

        require(fundingCompleted == false, "Funding already ended.");

        /*
            if((!fundingCompleted) && (checkDuration(2) <= 0))
            {
                revert("Proposal didnt match minimum funding requirements in time.");
            }
        */



        address funder = msg.sender;
        uint quantityToFund = paramFundingValue; //In wei.///
        uint apyRewards = (msg.value / percentage) * stakingApy;
        uint quantityWoApy = msg.value - apyRewards;


        require(msg.value >= (paramFundingValue + apyRewards), "Lack of funds sended.");

        uint valueToReturn = msg.value - (paramFundingValue + apyRewards);
        (bool returnExtra, ) = payable(funder).call{value: valueToReturn}("");
        require(returnExtra, "Ether transfer failed.");

        phaseTwoFunderOrder memory newPhaseTwoOrder = phaseTwoFunderOrder(funder, quantityToFund, apyRewards, quantityWoApy);



        uint orderFundedQuantity = ordersPhaseOne[actualOrderInFulfillment].quantityFunded;
        uint orderAlreadyFullfilledQuantity = orderQuantityFulfilled[actualOrderInFulfillment];

        bool completed = (orderAlreadyFullfilledQuantity == orderFundedQuantity);


        if(completed)
        {
            if(!orderPhaseOneFulfilled[actualOrderInFulfillment])
            {
                orderPhaseOneFulfilled[actualOrderInFulfillment] = true;
            }

            actualOrderInFulfillment++;
        }
        else if(!completed)
        {   
            while(quantityToFund != 0  && (actualOrderInFulfillment <= fundPhaseOneFinalId))
            {
                orderFundedQuantity = ordersPhaseOne[actualOrderInFulfillment].quantityFunded;
                orderAlreadyFullfilledQuantity = orderQuantityFulfilled[actualOrderInFulfillment];
                uint pendingQuantity = orderFundedQuantity - orderAlreadyFullfilledQuantity;

                if(quantityToFund > pendingQuantity)
                {
                    uint restOfQuantityToFund = quantityToFund - pendingQuantity;

                    orderPhaseOneFulfilled[actualOrderInFulfillment] = true;
                    actualOrderInFulfillment++;

                    if(actualOrderInFulfillment > fundPhaseOneFinalId)
                    {
                        fundingCompleted = true;

                        if(restOfQuantityToFund != 0)
                        {
                            (bool success, ) = payable(funder).call{value: restOfQuantityToFund}("");
                            require(success, "Returning rest of ether to owner failed.");
                        }
                    }
                    
                    quantityToFund = restOfQuantityToFund;
                }
                else if(quantityToFund < pendingQuantity)
                {
                    orderQuantityFulfilled[actualOrderInFulfillment] += quantityToFund;

                    quantityToFund = 0;
                }
                else if(quantityToFund == pendingQuantity)
                {
                    orderQuantityFulfilled[actualOrderInFulfillment] += quantityToFund;

                    orderPhaseOneFulfilled[actualOrderInFulfillment] = true;
                    actualOrderInFulfillment++;

                    if(actualOrderInFulfillment > fundPhaseOneFinalId)
                    {
                        fundingCompleted = true;
                    }

                    quantityToFund = 0;
                }
            }
        }


        ordersPhaseTwo[fundPhaseTwoOrdersNextId] = newPhaseTwoOrder;
        fundPhaseTwoOrdersNextId++;
    }

    function claimPhaseOneEther() public
    {
        uint fundedQuantity = quantityDeposited[msg.sender];
        require(fundedQuantity > 0, "Address didnt fund the project.");

        (bool success, ) = payable(msg.sender).call{value: fundedQuantity}("");
        require(success, "Returning phaseOneEther to funder failed.");
    }

    /*
    function claimPhaseTwoLiquidEther() public
    function claimEtherPlusRewards()
    */

   /*
    function checkDuration(uint paramPhase) private view returns(uint)
        {
            require(paramPhase == 1 || paramPhase == 2, "invalidPhase.");

            if(paramPhase == 1)
            {
                return((fundingPhaseOneTimeStamp + (daysOfFunding * (1 days))) - block.timestamp);
            }
            else if(paramPhase == 2)
            {
                return((fundingPhaseOneTimeStamp + (daysOfFunding * (2 days))) - block.timestamp);
            }
        }
    */
}
