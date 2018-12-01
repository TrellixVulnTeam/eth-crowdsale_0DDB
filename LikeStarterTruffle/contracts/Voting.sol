pragma solidity ^0.4.24;

import "./Likoin.sol";

contract Voting {

  // The token used for votes weights
  Likoin private _token;

  // The number of votes quantity able to validate a proposal
  uint private _minimumQuorum;
  
  // Minimum time before execution
  uint private _debatingPeriodInMinutes;
  
  // List of Proposals for Artifact generated by assignee
  mapping (uint => Proposal) private _proposals;
 
  // Number of Proposals
  uint private _numProposals;

  // Voting owner
  address private _owner;

  // Voting assignee, entity voting depends on 
  address private _assignee;

  /**
   * Event for a proposal added
   */
  event ProposalAdded(uint proposalID, uint artifact, uint amount, string description);
  
  /**
   * Event for a suggestion added
   */
  event SuggestionAdded(uint proposalID, uint suggestionID, address advisor, uint amount);
  
  /**
   * Event for a vote
   */
  event Voted(uint proposalID, uint suggestionID, address voter);
  
  /**
   * Event for a vote changed
   */
  event VoteChanged(uint proposalID, uint oldSuggestionID, uint newSuggestionID, address voter);
  
  /**
   * Event for a change in rules
   */
  event ChangeOfRules(uint newMinimumQuorum, uint newDebatingPeriodInMinutes);
  
  /**
   * Event for an execution
   */
  event ProposalExecuted(uint proposalID, bool proposalPassed, uint finalResult);
  
  /**
   * Structure used to manipulate a proposal for an artifact
   */
  struct Proposal {
    uint proposedArtifact;
    string description;
    mapping (uint => PriceSuggestion) suggestions;
    uint numSuggestions;
    mapping (address => uint256) balancesSnapshot;
    mapping (address => Vote) votes;

    uint minExecutionDate;
    bool executed;

    bool proposalPassed;
    uint finalResult;
  }

  /**
   * Structure used to manipulate a suggestion for a price
   */
  struct PriceSuggestion {
    address advisor;
    uint amount;
    mapping (uint => address) votes;
    uint numVotes;
    uint votesQuantity;
  }

  /**
   * Structure used to manipulate a vote of a single member
   */
  struct Vote {
    bool voted;
    uint suggestionID;
    uint voteID;
  }

  /**
   * @dev Modifier to allow only the owner
   */
  modifier onlyOwner() {
    require(isOwner(msg.sender));
    _;
  }

  /**
   * @dev Modifier to allow only the assignee
   */
  modifier onlyAssignee() {
    require(isAssignee(msg.sender));
    _;
  }

  /**
   * @dev Modifier to allow only members when the proposal has not been executed
   */
  modifier onlyMembersAndNotExecuted(uint proposalID) {
    require(proposalID < _numProposals);
    Proposal storage p = _proposals[proposalID];  
    require (!p.executed);
    require (p.balancesSnapshot[msg.sender] > 0 || msg.sender == _assignee || msg.sender == _owner);
    _;
  }

  /**
   * @param assignee Address of the entity vote depends on 
   * @param token Address of the token used for weight
   * @param minimumQuorumForProposals Number used to validate a vote in the execution
   * @param minutesForDebate Hours required before execution
   */
  constructor (address assignee, Likoin token, uint minimumQuorumForProposals, uint minutesForDebate) public {
    _owner = msg.sender;
    _assignee = assignee;
    _token = token;

    changeVotingRules(minimumQuorumForProposals, minutesForDebate);
  }

  /**
   * @dev Add Proposal
   */
  function newProposal(uint propArtifact, uint buckAmount, string memory artifactDescription) onlyAssignee public returns (uint proposalID) {
    proposalID = _numProposals++;
    Proposal storage p = _proposals[proposalID];
    p.proposedArtifact = propArtifact;
    for(uint i = 1; i <= _token.getBalanceHoldersLength(); i++){
      address holder = _token.getBalanceHolder(i);
      p.balancesSnapshot[holder] = _token.balanceOf(holder); 
    }
    p.minExecutionDate = now + _debatingPeriodInMinutes * 1 hours;
    p.description = artifactDescription;
    
    newPriceSuggestion(proposalID, buckAmount);

    p.executed = false;
    p.proposalPassed = false;
    emit ProposalAdded(proposalID, propArtifact, buckAmount, artifactDescription);
  
    return proposalID;
  }

  /**
   * @dev Add Suggestion
   */
  function newPriceSuggestion(uint proposalID, uint buckAmount) public onlyMembersAndNotExecuted(proposalID) returns (uint suggestionID) {
    Proposal storage p = _proposals[proposalID];

    suggestionID = p.numSuggestions++;
    PriceSuggestion storage s = p.suggestions[suggestionID];
    s.advisor = msg.sender;
    s.amount = buckAmount;

    emit SuggestionAdded(proposalID, suggestionID, msg.sender, buckAmount);
    return suggestionID;
  }

  /**
   * @dev Log a vote for a proposal
   */
  function vote(uint proposalID, uint suggestionID) public onlyMembersAndNotExecuted(proposalID) returns (uint voteID) {
    Proposal storage p = _proposals[proposalID];
    Vote storage v = p.votes[msg.sender];
    require(!v.voted);

    require(suggestionID < p.numSuggestions);
    PriceSuggestion storage s = p.suggestions[suggestionID];

    v.voted = true;  
    v.suggestionID = suggestionID;    
    v.voteID = s.numVotes++;
    s.votes[v.voteID] = msg.sender;
    s.votesQuantity += p.balancesSnapshot[msg.sender];

    emit Voted(proposalID, suggestionID, msg.sender);
    return v.voteID;
  }

  /**
   * @dev Change vote for a proposal
   */
  function changeVote(uint proposalID, uint newSuggestionID) public onlyMembersAndNotExecuted(proposalID) returns (uint voteID) {
    Proposal storage p = _proposals[proposalID];
    Vote storage v = p.votes[msg.sender];
    require(v.voted);
    require (v.suggestionID != newSuggestionID);    
    require(newSuggestionID < p.numSuggestions);
    
    uint oldSuggestionID = v.suggestionID;
    v.suggestionID = newSuggestionID;
    PriceSuggestion storage oldSuggestion = p.suggestions[oldSuggestionID];
    PriceSuggestion storage newSuggestion = p.suggestions[newSuggestionID];

    uint256 index = v.voteID;
    if(oldSuggestion.numVotes > 1){
      address last = oldSuggestion.votes[oldSuggestion.numVotes - 1];
      oldSuggestion.votes[index] = last;
      Vote storage vLast = p.votes[last];
      vLast.voteID = index;
    }
    oldSuggestion.numVotes--;
    oldSuggestion.votesQuantity -= p.balancesSnapshot[msg.sender];

    v.voteID = newSuggestion.numVotes++;
    newSuggestion.votes[v.voteID] = msg.sender;
    newSuggestion.votesQuantity += p.balancesSnapshot[msg.sender];

    // Create a log of this event
    emit VoteChanged(proposalID, oldSuggestionID, newSuggestionID, msg.sender);
    return v.voteID;
  }

  /**
   * @dev Finish vote, count the votes proposal and execute
   */
  function executeProposal(uint proposalID) public onlyOwner {
    require(proposalID < _numProposals);
    Proposal storage p = _proposals[proposalID];
    require(now >= p.minExecutionDate && !p.executed);                         

    p.executed = true;
    uint256 tmpMax = 0;
    uint256 tmpTotal = p.suggestions[0].votesQuantity;
    for(uint i = 1; i < p.numSuggestions; i++){
      tmpTotal += p.suggestions[i].votesQuantity;
      if(p.suggestions[i].votesQuantity > p.suggestions[tmpMax].votesQuantity) {
        tmpMax = i;
      }
    }
    
    if(tmpTotal > _minimumQuorum){
      p.proposalPassed = true;
      p.finalResult = 0;
    } else {
      p.proposalPassed = false;
    }

    emit ProposalExecuted(proposalID, p.proposalPassed, p.finalResult);
  }

  /**
   * @dev Change voting rules
   */
  function changeVotingRules(uint minimumQuorumForProposals, uint minutesForDebate) public onlyOwner {
    _minimumQuorum = minimumQuorumForProposals;
    _debatingPeriodInMinutes = minutesForDebate;

    emit ChangeOfRules(minimumQuorumForProposals, minutesForDebate);
  }

  /**
   * @return The token being used
   */
  function token() public view returns(Likoin) {
    return _token;
  }

  /**
  * @return Minimum Quorum
  */
  function minimumQuorum() public view returns (uint) {
    return _minimumQuorum;
  }

  /**
  * @return Debating period in hours
  */
  function debatingPeriodInMinutes() public view returns (uint) {
    return _debatingPeriodInMinutes;
  }

  /**
  * @return Get proposal id by artifact
  */
  function getProposalIdByArtifact(uint artifact) public view returns (uint) {
    for(uint i = 0; i < _numProposals; i++ ) {
      if(_proposals[i].proposedArtifact == artifact ){
        return i;
      }
    }
    require(false);
  }

  /**
  * @return true if a proposal is executed
  */
  function isExecuted(uint proposalID) public view returns (bool) {
    require(proposalID < _numProposals);
    return _proposals[proposalID].executed;
  }  

  /**
  * @return Get proposal final result
  */
  function getProposalFinalResult(uint proposalID) public view returns (uint) {
    require(proposalID < _numProposals);
    if(isExecuted(proposalID)){
      return _proposals[proposalID].finalResult;
    }
    else{
      require(false);
    }
  }

  /**
  * @return Number of proposals
  */
  function numberOfProposals() public view returns (uint) {
    return _numProposals;
  }

  /**
  * @return Amount of proposal suggestion
  */
  function getProposalSuggestionAmount(uint proposalID, uint suggestionID) public view returns (uint) {
    require(proposalID < _numProposals);
    require(suggestionID < _proposals[proposalID].numSuggestions);
    return _proposals[proposalID].suggestions[suggestionID].amount;
  }

  /**
  * @return Number of votes of proposal suggestion
  */
  function getProposalSuggestionVotes(uint proposalID, uint suggestionID) public view returns (uint) {
    require(proposalID < _numProposals);
    require(suggestionID < _proposals[proposalID].numSuggestions);
    return _proposals[proposalID].suggestions[suggestionID].numVotes;
  }

  /**
  * @return Quantity of votes of proposal suggestion
  */
  function getProposalSuggestionVotesQuantity(uint proposalID, uint suggestionID) public view returns (uint) {
    require(proposalID < _numProposals);
    require(suggestionID < _proposals[proposalID].numSuggestions);
    return _proposals[proposalID].suggestions[suggestionID].votesQuantity;
  }

  /**
  * @return Number of proposals suggestions
  */
  function numberOfProposalSuggestions(uint proposalID) public view returns (uint) {
    require(proposalID < _numProposals);
    return _proposals[proposalID].numSuggestions;
  }

  /**
  * @return true if account voted for suggestionID in proposalID
  */
  function hasVotedFor(address account, uint proposalID, uint suggestionID) public view returns (bool) {
    require(proposalID < _numProposals);
    require(suggestionID < _proposals[proposalID].numSuggestions);
    return _proposals[proposalID].votes[account].suggestionID == suggestionID;
  }


  /**
  * @return Owner of voting
  */
  function owner() public view returns (address) {
    return _owner;
  }

  /**
   * @dev Function indicating if account is owner 
   */
  function isOwner(address account) public view returns (bool) {
    return _owner == account;
  }

  /**
  * @return Assignee of voting
  */
  function assignee() public view returns (address) {
    return _assignee;
  }

  /**
   * @dev Function indicating if account is assignee 
   */
  function isAssignee(address account) public view returns (bool) {
    return _assignee == account;
  }
}


