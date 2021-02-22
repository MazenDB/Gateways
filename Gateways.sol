pragma solidity =0.6.0;

contract Registration {
    
    struct gatewaytype{
        uint rating;
        uint raters;
        uint deposit;
    }
    address payable owner;
    mapping(address=>bool) public clients;
    mapping(address=>gatewaytype) public gateways;
    mapping(uint=>address) public GWcounter;
    uint constant clientRegisterationFee=1;
    uint constant GWDeposit=100;
    uint constant penaltyAmount=10;
    uint public validators;

    event ClientRegistered(address client);
    event GatewayRegistered(address gateway);
    event BalanceDeducted(address validator, uint amountDeducted);

    
    constructor() public{
        owner=msg.sender;
        validators=0;
    }
    
    function registerClient() public payable{
        require(!clients[msg.sender] && gateways[msg.sender].rating==0,
        "Address already used");
        
        require(msg.value==clientRegisterationFee,
        "Admission fee incorrect");
        
        clients[msg.sender]=true;
        emit ClientRegistered(msg.sender);
    }
    
    function registerGateway() public payable{
        require(!clients[msg.sender] && gateways[msg.sender].rating==0,
        "Address already used");

        require(msg.value==GWDeposit,
        "Admission fee incorrect");

        gateways[msg.sender]=gatewaytype(80,0,msg.value);
        GWcounter[validators++]=msg.sender;
        emit GatewayRegistered(msg.sender);
    }
    

    function clientExists(address c) public view returns(bool){
        return clients[c];
    }

    function getGWRating(address g) public view returns(uint){
        return gateways[g].rating;
    }

    function getGWRaters(address g) public view returns(uint){
        return gateways[g].raters;
    }

    function setGWRating(address g, uint newRating) public{
        if(newRating>100){
            gateways[g].rating=100;
        }
        else if (newRating<50){
            gateways[g].rating=0;
        }
        else{
            gateways[g].rating=newRating;
        }
        
        gateways[g].raters++;
    }
    
    function isOwner(address payable o) public view returns(bool){
        return (o==owner);
    }
    
    function availableValidators() public view returns(uint){
        return (validators);
    }
    
    function decreaseAvailableValidators(uint requiredValidators) public{
        validators-=requiredValidators;
    }
    
    function increaseAvailableValidators(uint requiredValidators) public{
        validators-=requiredValidators;
    }
    
    function getGWAddress(uint GWnum) public view returns(address){
        return GWcounter[GWnum];
    }

    
    function deductBalance(address validator,address payable client, uint validatorNum) public {
        if(gateways[validator].deposit<=penaltyAmount){
            require(GWcounter[validatorNum]==validator,
            "Validator number does not map to the validator address");

            gateways[validator].deposit=0;  
            gateways[validator].rating=0;
            validators--;
            GWcounter[validatorNum]=GWcounter[validators];
        }
        else{
            gateways[validator].deposit-=penaltyAmount;

        }
        emit BalanceDeducted(validator, penaltyAmount);
        client.transfer(penaltyAmount);


    }
}

contract Validation{
    
    struct validatorsCount{
        address client;
        uint requestedValidators;
        uint remainingValidators;
    }
    
    Registration registrationContract;
    uint public requestNumber;
    mapping(uint=>validatorsCount) public attestationRequests;
    uint currentValidator;
    uint constant feePerValidator=5;
    uint constant validationPayment=4;
    mapping(address=>uint) public activeValidators;
    
    event ValidationRequired(uint requestNumber,address validator, uint validatorNum);
    event RequestConfirmed(uint requestNumber, address clientAddress);

     modifier onlyClient{
      require(registrationContract.clientExists(msg.sender),
      "Sender not authorized."
      );
      _;
    }  
    
     modifier onlyGW{
      require(registrationContract.getGWRating(msg.sender)!=0,
      "Sender not authorized."
      );
      _;
    }  
    
    constructor(address registrationAddress)public {
        registrationContract=Registration(registrationAddress);
        requestNumber=uint(keccak256(abi.encodePacked(msg.sender,now,address(this))));
        currentValidator=0;
    }
    
    function requestAttestation(uint numofValidators) public payable onlyClient{
        uint availableVals=registrationContract.availableValidators();
        require(availableVals>numofValidators,
        "Number of available validators is insufficient."
        );
        
        require(attestationRequests[requestNumber].requestedValidators==0,
        "Attestation already requested by this client."
        );
        
        require(msg.value==feePerValidator*numofValidators,
        "Validation Fee incorrect."
        );
        attestationRequests[requestNumber]=validatorsCount(msg.sender, numofValidators, numofValidators);
        registrationContract.decreaseAvailableValidators(numofValidators);
        
        address tempV;
        for(uint i=0;i<numofValidators;i++){

            tempV=registrationContract.getGWAddress(currentValidator);
            if(tempV==msg.sender){
                tempV=registrationContract.getGWAddress(++currentValidator);
            }
            activeValidators[tempV]=requestNumber;
            emit ValidationRequired(requestNumber, tempV,currentValidator);
            currentValidator=(currentValidator+1==availableVals)?0:currentValidator+1;
            
        }
        
        emit RequestConfirmed(requestNumber, msg.sender);
        requestNumber++;
    }
    
    function TxAttested(uint requestNum) public onlyGW{
        require(attestationRequests[requestNum].requestedValidators>0,
        "Request Number is invalid."
        );

        require(activeValidators[msg.sender]==requestNum,
        "Validator GW is not assigned to this Attestation Request."
        );
        
        msg.sender.transfer(validationPayment);
        
        activeValidators[msg.sender]=0;
        attestationRequests[requestNum].remainingValidators--;
        if(attestationRequests[requestNum].remainingValidators==0)
        {
            registrationContract.increaseAvailableValidators(attestationRequests[requestNum].requestedValidators);
            attestationRequests[requestNum].requestedValidators=0;
        }
    }
    
    function rateGateway(address GWAddress, uint rating) public onlyClient{
        uint temprating=registrationContract.getGWRating(GWAddress);
        uint tempraters=registrationContract.getGWRaters(GWAddress);
        
        registrationContract.setGWRating(GWAddress,(temprating*tempraters+rating)/tempraters+1);    
    }
    
    function reportMissingAttestations(uint requestNum, address validator, uint validatorNum) public onlyClient{
        require(attestationRequests[requestNum].requestedValidators>0,
        "Request Number is invalid."
        );

        require(attestationRequests[requestNum].client==msg.sender,
        "Client not auhtorized."
        );
        
        if(attestationRequests[requestNum].remainingValidators!=0){
            registrationContract.increaseAvailableValidators(attestationRequests[requestNum].requestedValidators);
        }
        attestationRequests[requestNum].requestedValidators=0;
        registrationContract.deductBalance(validator, msg.sender, validatorNum);
    }
}
