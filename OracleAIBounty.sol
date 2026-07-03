// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract OracleAIBounty {
    struct Challenge {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 oracleDeadline;
        bool finalized;
        address winner;
        string[] answers;
        address[] participants;
        mapping(address => bytes32) commitments;
        mapping(address => bool) hasRevealed;
        mapping(address => uint256) answerIndex;
        mapping(address => uint256) oracleVotes;
        mapping(address => bool) oracleVoted;
        uint256 totalOracleVotes;
        uint256 oracleCount;
        address[] oracles;
        mapping(address => uint256) oracleStakes;
        mapping(address => bool) isOracle;
    }

    struct ChallengeInfo {
        address owner;
        string prompt;
        uint256 reward;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 oracleDeadline;
        bool finalized;
        address winner;
        uint256 participantCount;
        uint256 answerCount;
        uint256 totalOracleVotes;
        uint256 oracleCount;
    }

    uint256 public challengeCounter;
    mapping(uint256 => Challenge) public challenges;

    uint256 public constant ORACLE_STAKE = 0.1 ether;

    event ChallengeCreated(uint256 indexed id, address indexed owner, uint256 reward);
    event CommitmentSubmitted(uint256 indexed id, address indexed participant);
    event AnswerRevealed(uint256 indexed id, address indexed participant, string answer);
    event OracleAdded(uint256 indexed id, address indexed oracle);
    event OracleVoted(uint256 indexed id, address indexed oracle, address indexed winner);
    event WinnerFinalized(uint256 indexed id, address indexed winner);

    modifier challengeExists(uint256 id) {
        require(challenges[id].owner != address(0), "Challenge does not exist");
        _;
    }

    modifier onlyCommitPhase(uint256 id) {
        require(block.timestamp <= challenges[id].commitDeadline, "Commit phase ended");
        _;
    }

    modifier onlyRevealPhase(uint256 id) {
        require(block.timestamp > challenges[id].commitDeadline, "Not reveal phase");
        require(block.timestamp <= challenges[id].revealDeadline, "Reveal phase ended");
        _;
    }

    modifier onlyOraclePhase(uint256 id) {
        require(block.timestamp > challenges[id].revealDeadline, "Not oracle phase");
        require(block.timestamp <= challenges[id].oracleDeadline, "Oracle phase ended");
        _;
    }

    modifier onlyAfterOracle(uint256 id) {
        require(block.timestamp > challenges[id].oracleDeadline, "Oracle phase not over");
        _;
    }

    modifier onlyOwner(uint256 id) {
        require(msg.sender == challenges[id].owner, "Not challenge owner");
        _;
    }

    modifier notFinalized(uint256 id) {
        require(!challenges[id].finalized, "Already finalized");
        _;
    }

    function createChallenge(
        string calldata prompt,
        uint256 commitDeadline,
        uint256 revealDuration,
        uint256 oracleDuration
    ) external payable {
        require(msg.value > 0, "Reward must be > 0 RIT");
        require(commitDeadline > block.timestamp, "Deadline must be in future");
        require(revealDuration > 0, "Reveal duration must be > 0");
        require(oracleDuration > 0, "Oracle duration must be > 0");

        uint256 id = challengeCounter++;
        Challenge storage c = challenges[id];
        c.owner = msg.sender;
        c.prompt = prompt;
        c.reward = msg.value;
        c.commitDeadline = commitDeadline;
        c.revealDeadline = commitDeadline + revealDuration;
        c.oracleDeadline = c.revealDeadline + oracleDuration;

        emit ChallengeCreated(id, msg.sender, msg.value);
    }

    function submitCommitment(uint256 id, bytes32 commitment) external 
        challengeExists(id)
        onlyCommitPhase(id)
    {
        Challenge storage c = challenges[id];
        require(c.commitments[msg.sender] == 0, "Already committed");

        c.commitments[msg.sender] = commitment;
        c.participants.push(msg.sender);

        emit CommitmentSubmitted(id, msg.sender);
    }

    function revealAnswer(
        uint256 id,
        string calldata answer,
        bytes32 salt
    ) external 
        challengeExists(id)
        onlyRevealPhase(id)
    {
        Challenge storage c = challenges[id];
        bytes32 commitment = c.commitments[msg.sender];
        require(commitment != 0, "No commitment found");
        require(!c.hasRevealed[msg.sender], "Already revealed");

        bytes32 computed = keccak256(abi.encodePacked(answer, salt, msg.sender, id));
        require(computed == commitment, "Commitment mismatch");

        c.hasRevealed[msg.sender] = true;
        c.answerIndex[msg.sender] = c.answers.length;
        c.answers.push(answer);

        emit AnswerRevealed(id, msg.sender, answer);
    }

    function addOracle(uint256 id) external payable 
        challengeExists(id)
        onlyRevealPhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(!c.isOracle[msg.sender], "Already an oracle");
        require(msg.value >= ORACLE_STAKE, "Stake too low");

        c.isOracle[msg.sender] = true;
        c.oracleStakes[msg.sender] = msg.value;
        c.oracles.push(msg.sender);
        c.oracleCount++;

        emit OracleAdded(id, msg.sender);
    }

    function voteOracle(
        uint256 id,
        address winner
    ) external 
        challengeExists(id)
        onlyOraclePhase(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.isOracle[msg.sender], "Not an oracle for this challenge");
        require(!c.oracleVoted[msg.sender], "Already voted");
        require(c.hasRevealed[winner], "Winner must have revealed");

        c.oracleVotes[winner] += 1;
        c.totalOracleVotes += 1;
        c.oracleVoted[msg.sender] = true;

        emit OracleVoted(id, msg.sender, winner);
    }

    function finalizeWinner(uint256 id) external 
        challengeExists(id)
        onlyOwner(id)
        onlyAfterOracle(id)
        notFinalized(id)
    {
        Challenge storage c = challenges[id];
        require(c.totalOracleVotes > 0, "No oracle votes");
        require(c.oracleCount > 0, "No oracles added");

        address winner = address(0);
        uint256 maxVotes = 0;

        for (uint i = 0; i < c.participants.length; i++) {
            address participant = c.participants[i];
            if (!c.hasRevealed[participant]) continue;
            
            uint256 votes = c.oracleVotes[participant];
            if (votes > maxVotes) {
                maxVotes = votes;
                winner = participant;
            }
        }

        require(winner != address(0), "No valid winner found");

        c.finalized = true;
        c.winner = winner;

        // Return stakes to all oracles
        for (uint i = 0; i < c.oracles.length; i++) {
            address oracle = c.oracles[i];
            uint256 stake = c.oracleStakes[oracle];
            if (stake > 0) {
                c.oracleStakes[oracle] = 0;
                payable(oracle).transfer(stake);
            }
        }

        payable(winner).transfer(c.reward);

        emit WinnerFinalized(id, winner);
    }

    function getChallengeInfo(uint256 id) external view returns (ChallengeInfo memory) {
        Challenge storage c = challenges[id];
        return ChallengeInfo({
            owner: c.owner,
            prompt: c.prompt,
            reward: c.reward,
            commitDeadline: c.commitDeadline,
            revealDeadline: c.revealDeadline,
            oracleDeadline: c.oracleDeadline,
            finalized: c.finalized,
            winner: c.winner,
            participantCount: c.participants.length,
            answerCount: c.answers.length,
            totalOracleVotes: c.totalOracleVotes,
            oracleCount: c.oracleCount
        });
    }

    function getAnswers(uint256 id) external view returns (string[] memory) {
        require(msg.sender == challenges[id].owner || challenges[id].finalized, "Not authorized");
        return challenges[id].answers;
    }

    function getOracleVotes(uint256 id, address participant) external view returns (uint256) {
        return challenges[id].oracleVotes[participant];
    }

    function getOracles(uint256 id) external view returns (address[] memory) {
        return challenges[id].oracles;
    }

    function hasCommitted(uint256 id, address participant) external view returns (bool) {
        return challenges[id].commitments[participant] != 0;
    }

    function hasRevealed(uint256 id, address participant) external view returns (bool) {
        return challenges[id].hasRevealed[participant];
    }

    function isOracleForChallenge(uint256 id, address participant) external view returns (bool) {
        return challenges[id].isOracle[participant];
    }
}
