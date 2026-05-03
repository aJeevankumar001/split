// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address from, address to, uint amount)
        external
        returns (bool);

    function transfer(address to, uint amount)
        external
        returns (bool);
}

contract SplitBillPro {
    address public owner;
    IERC20 public usdcToken;

    uint public groupCount;

    constructor(address _usdcToken) {
        owner = msg.sender;
        usdcToken = IERC20(_usdcToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    struct Group {
        string name;
        address[] members;
        mapping(address => bool) isMember;
    }

    struct Expense {
        string description;
        uint amount;
        address payer;
        address[] participants;
        string currency;
    }

    mapping(uint => Group) private groups;
    mapping(uint => Expense[]) private expenses;

    // ETH balance: groupId => from => to => amount
    mapping(uint => mapping(address => mapping(address => uint))) public balances;

    // USDC balance: groupId => from => to => amount
    mapping(uint => mapping(address => mapping(address => uint))) public usdcBalances;

    // ------------------ SET USDC TOKEN ------------------

    function setUSDCToken(address _usdcToken) public onlyOwner {
        require(_usdcToken != address(0), "Invalid token address");
        usdcToken = IERC20(_usdcToken);
    }

    // ------------------ CREATE GROUP ------------------

    function createGroup(string memory _name, address[] memory _members) public {
        require(bytes(_name).length > 0, "Group name required");
        require(_members.length > 0, "Add members");

        Group storage g = groups[groupCount];
        g.name = _name;

        bool creatorAdded = false;

        for (uint i = 0; i < _members.length; i++) {
            require(_members[i] != address(0), "Invalid member");

            if (!g.isMember[_members[i]]) {
                g.members.push(_members[i]);
                g.isMember[_members[i]] = true;
            }

            if (_members[i] == msg.sender) {
                creatorAdded = true;
            }
        }

        if (!creatorAdded) {
            g.members.push(msg.sender);
            g.isMember[msg.sender] = true;
        }

        groupCount++;
    }

    // ------------------ GET GROUP NAME ------------------

    function getGroupName(uint groupId) public view returns (string memory) {
        require(groupId < groupCount, "Invalid group");
        return groups[groupId].name;
    }

    // ------------------ IS MEMBER ------------------

    function isMember(uint groupId, address user) public view returns (bool) {
        require(groupId < groupCount, "Invalid group");
        return groups[groupId].isMember[user];
    }

    // ------------------ GET MEMBERS ------------------

    function getMembers(uint groupId) public view returns (address[] memory) {
        require(groupId < groupCount, "Invalid group");
        return groups[groupId].members;
    }

    // ------------------ VALIDATE EXPENSE ------------------

    function _validateExpense(
        uint groupId,
        address[] memory _participants
    ) internal view {
        require(groupId < groupCount, "Invalid group");

        Group storage g = groups[groupId];

        require(g.isMember[msg.sender], "Payer not member");
        require(_participants.length > 0, "Add participants");

        for (uint i = 0; i < _participants.length; i++) {
            require(_participants[i] != address(0), "Invalid participant");
            require(g.isMember[_participants[i]], "Participant not member");
            require(_participants[i] != msg.sender, "Payer already included");

            for (uint j = i + 1; j < _participants.length; j++) {
                require(
                    _participants[i] != _participants[j],
                    "Duplicate participant"
                );
            }
        }
    }

    // ------------------ ADD ETH EXPENSE ------------------

    function addExpense(
        uint groupId,
        string memory _desc,
        uint _amount,
        address[] memory _participants
    ) public {
        require(_amount > 0, "Amount must be greater than zero");

        _validateExpense(groupId, _participants);

        uint totalPeople = _participants.length + 1;
        uint share = _amount / totalPeople;

        require(share > 0, "Amount too small");

        for (uint i = 0; i < _participants.length; i++) {
            address user = _participants[i];
            balances[groupId][user][msg.sender] += share;
        }

        expenses[groupId].push(
            Expense(_desc, _amount, msg.sender, _participants, "ETH")
        );
    }

    // ------------------ ADD USDC EXPENSE ------------------

    function addUSDCExpense(
        uint groupId,
        string memory _desc,
        uint _amount,
        address[] memory _participants
    ) public {
        require(_amount > 0, "Amount must be greater than zero");

        _validateExpense(groupId, _participants);

        uint totalPeople = _participants.length + 1;
        uint share = _amount / totalPeople;

        require(share > 0, "Amount too small");

        for (uint i = 0; i < _participants.length; i++) {
            address user = _participants[i];
            usdcBalances[groupId][user][msg.sender] += share;
        }

        expenses[groupId].push(
            Expense(_desc, _amount, msg.sender, _participants, "USDC")
        );
    }

    // ------------------ GET ETH BALANCE ------------------

    function getBalance(
        uint groupId,
        address from,
        address to
    ) public view returns (uint) {
        require(groupId < groupCount, "Invalid group");
        return balances[groupId][from][to];
    }

    // ------------------ GET USDC BALANCE ------------------

    function getUSDCBalance(
        uint groupId,
        address from,
        address to
    ) public view returns (uint) {
        require(groupId < groupCount, "Invalid group");
        return usdcBalances[groupId][from][to];
    }

    // ------------------ ETH NET BALANCE ------------------

    function getNetBalance(
        uint groupId,
        address user
    ) public view returns (int) {
        require(groupId < groupCount, "Invalid group");

        Group storage g = groups[groupId];
        require(g.isMember[user], "User not member");

        int net = 0;

        for (uint i = 0; i < g.members.length; i++) {
            address other = g.members[i];

            if (user == other) {
                continue;
            }

            net += int(balances[groupId][other][user]);
            net -= int(balances[groupId][user][other]);
        }

        return net;
    }

    // ------------------ USDC NET BALANCE ------------------

    function getUSDCNetBalance(
        uint groupId,
        address user
    ) public view returns (int) {
        require(groupId < groupCount, "Invalid group");

        Group storage g = groups[groupId];
        require(g.isMember[user], "User not member");

        int net = 0;

        for (uint i = 0; i < g.members.length; i++) {
            address other = g.members[i];

            if (user == other) {
                continue;
            }

            net += int(usdcBalances[groupId][other][user]);
            net -= int(usdcBalances[groupId][user][other]);
        }

        return net;
    }

    // ------------------ PAY DIRECT ETH DEBT ------------------

    function payDebt(uint groupId, address to) public payable {
        require(groupId < groupCount, "Invalid group");
        require(to != address(0), "Invalid receiver");

        uint amount = balances[groupId][msg.sender][to];

        require(amount > 0, "No debt");
        require(msg.value == amount, "Wrong ETH amount");

        balances[groupId][msg.sender][to] = 0;

        payable(to).transfer(msg.value);
    }

    // ------------------ PAY DIRECT USDC DEBT ------------------

    function payUSDCDebt(uint groupId, address to) public {
        require(groupId < groupCount, "Invalid group");
        require(to != address(0), "Invalid receiver");

        uint amount = usdcBalances[groupId][msg.sender][to];

        require(amount > 0, "No USDC debt");

        usdcBalances[groupId][msg.sender][to] = 0;

        bool success = usdcToken.transferFrom(msg.sender, to, amount);
        require(success, "USDC transfer failed");
    }

    // ------------------ EXPENSE COUNT ------------------

    function getExpensesCount(uint groupId) public view returns (uint) {
        require(groupId < groupCount, "Invalid group");
        return expenses[groupId].length;
    }

    // ------------------ GET EXPENSE ------------------

    function getExpense(
        uint groupId,
        uint index
    )
        public
        view
        returns (
            string memory description,
            uint amount,
            address payer,
            address[] memory participants,
            string memory currency
        )
    {
        require(groupId < groupCount, "Invalid group");
        require(index < expenses[groupId].length, "Invalid expense index");

        Expense memory e = expenses[groupId][index];

        return (
            e.description,
            e.amount,
            e.payer,
            e.participants,
            e.currency
        );
    }

    // ------------------ SIMPLIFY ETH DEBTS ------------------

    function simplifyDebts(
        uint groupId
    )
        public
        view
        returns (
            address[] memory from,
            address[] memory to,
            uint[] memory amount
        )
    {
        require(groupId < groupCount, "Invalid group");

        Group storage g = groups[groupId];
        uint n = g.members.length;

        int[] memory net = new int[](n);

        for (uint i = 0; i < n; i++) {
            net[i] = getNetBalance(groupId, g.members[i]);
        }

        address[] memory tempFrom = new address[](n);
        address[] memory tempTo = new address[](n);
        uint[] memory tempAmount = new uint[](n);

        uint k = 0;

        for (uint i = 0; i < n; i++) {
            if (net[i] < 0) {
                for (uint j = 0; j < n; j++) {
                    if (net[j] > 0) {
                        uint debtAmount = uint(-net[i]);
                        uint creditAmount = uint(net[j]);

                        uint minAmount = debtAmount < creditAmount
                            ? debtAmount
                            : creditAmount;

                        net[i] += int(minAmount);
                        net[j] -= int(minAmount);

                        tempFrom[k] = g.members[i];
                        tempTo[k] = g.members[j];
                        tempAmount[k] = minAmount;

                        k++;

                        if (net[i] == 0) {
                            break;
                        }
                    }
                }
            }
        }

        from = new address[](k);
        to = new address[](k);
        amount = new uint[](k);

        for (uint i = 0; i < k; i++) {
            from[i] = tempFrom[i];
            to[i] = tempTo[i];
            amount[i] = tempAmount[i];
        }
    }

    // ------------------ SIMPLIFY USDC DEBTS ------------------

    function simplifyUSDCDebts(
        uint groupId
    )
        public
        view
        returns (
            address[] memory from,
            address[] memory to,
            uint[] memory amount
        )
    {
        require(groupId < groupCount, "Invalid group");

        Group storage g = groups[groupId];
        uint n = g.members.length;

        int[] memory net = new int[](n);

        for (uint i = 0; i < n; i++) {
            net[i] = getUSDCNetBalance(groupId, g.members[i]);
        }

        address[] memory tempFrom = new address[](n);
        address[] memory tempTo = new address[](n);
        uint[] memory tempAmount = new uint[](n);

        uint k = 0;

        for (uint i = 0; i < n; i++) {
            if (net[i] < 0) {
                for (uint j = 0; j < n; j++) {
                    if (net[j] > 0) {
                        uint debtAmount = uint(-net[i]);
                        uint creditAmount = uint(net[j]);

                        uint minAmount = debtAmount < creditAmount
                            ? debtAmount
                            : creditAmount;

                        net[i] += int(minAmount);
                        net[j] -= int(minAmount);

                        tempFrom[k] = g.members[i];
                        tempTo[k] = g.members[j];
                        tempAmount[k] = minAmount;

                        k++;

                        if (net[i] == 0) {
                            break;
                        }
                    }
                }
            }
        }

        from = new address[](k);
        to = new address[](k);
        amount = new uint[](k);

        for (uint i = 0; i < k; i++) {
            from[i] = tempFrom[i];
            to[i] = tempTo[i];
            amount[i] = tempAmount[i];
        }
    }

    // ------------------ APPLY SIMPLIFIED ETH SETTLEMENT ------------------

    function _applySimplifiedETHSettlement(
        uint groupId,
        address debtor,
        address creditor,
        uint amount
    ) internal {
        Group storage g = groups[groupId];

        uint remainingOutgoing = amount;

        for (uint i = 0; i < g.members.length && remainingOutgoing > 0; i++) {
            address member = g.members[i];
            uint debt = balances[groupId][debtor][member];

            if (debt > 0) {
                uint reduceAmount = debt < remainingOutgoing
                    ? debt
                    : remainingOutgoing;

                balances[groupId][debtor][member] -= reduceAmount;
                remainingOutgoing -= reduceAmount;
            }
        }

        require(remainingOutgoing == 0, "Debtor reduction failed");

        uint remainingIncoming = amount;

        for (uint i = 0; i < g.members.length && remainingIncoming > 0; i++) {
            address member = g.members[i];
            uint credit = balances[groupId][member][creditor];

            if (credit > 0) {
                uint reduceAmount = credit < remainingIncoming
                    ? credit
                    : remainingIncoming;

                balances[groupId][member][creditor] -= reduceAmount;
                remainingIncoming -= reduceAmount;
            }
        }

        require(remainingIncoming == 0, "Creditor reduction failed");
    }

    // ------------------ APPLY SIMPLIFIED USDC SETTLEMENT ------------------

    function _applySimplifiedUSDCSettlement(
        uint groupId,
        address debtor,
        address creditor,
        uint amount
    ) internal {
        Group storage g = groups[groupId];

        uint remainingOutgoing = amount;

        for (uint i = 0; i < g.members.length && remainingOutgoing > 0; i++) {
            address member = g.members[i];
            uint debt = usdcBalances[groupId][debtor][member];

            if (debt > 0) {
                uint reduceAmount = debt < remainingOutgoing
                    ? debt
                    : remainingOutgoing;

                usdcBalances[groupId][debtor][member] -= reduceAmount;
                remainingOutgoing -= reduceAmount;
            }
        }

        require(remainingOutgoing == 0, "Debtor reduction failed");

        uint remainingIncoming = amount;

        for (uint i = 0; i < g.members.length && remainingIncoming > 0; i++) {
            address member = g.members[i];
            uint credit = usdcBalances[groupId][member][creditor];

            if (credit > 0) {
                uint reduceAmount = credit < remainingIncoming
                    ? credit
                    : remainingIncoming;

                usdcBalances[groupId][member][creditor] -= reduceAmount;
                remainingIncoming -= reduceAmount;
            }
        }

        require(remainingIncoming == 0, "Creditor reduction failed");
    }

    // ------------------ PAY SIMPLIFIED ETH DEBT ------------------

    function paySimplifiedDebt(
        uint groupId,
        address to,
        uint amount
    ) public payable {
        require(groupId < groupCount, "Invalid group");
        require(to != address(0), "Invalid receiver");
        require(amount > 0, "Amount must be greater than zero");
        require(msg.value == amount, "Wrong ETH amount");

        int debtorNet = getNetBalance(groupId, msg.sender);
        int creditorNet = getNetBalance(groupId, to);

        require(debtorNet < 0, "You are not debtor");
        require(creditorNet > 0, "Receiver is not creditor");

        uint maxPayable = uint(-debtorNet) < uint(creditorNet)
            ? uint(-debtorNet)
            : uint(creditorNet);

        require(amount <= maxPayable, "Amount exceeds simplified debt");

        _applySimplifiedETHSettlement(groupId, msg.sender, to, amount);

        payable(to).transfer(amount);
    }

    // ------------------ PAY SIMPLIFIED USDC DEBT ------------------

    function paySimplifiedUSDCDebt(
        uint groupId,
        address to,
        uint amount
    ) public {
        require(groupId < groupCount, "Invalid group");
        require(to != address(0), "Invalid receiver");
        require(amount > 0, "Amount must be greater than zero");

        int debtorNet = getUSDCNetBalance(groupId, msg.sender);
        int creditorNet = getUSDCNetBalance(groupId, to);

        require(debtorNet < 0, "You are not debtor");
        require(creditorNet > 0, "Receiver is not creditor");

        uint maxPayable = uint(-debtorNet) < uint(creditorNet)
            ? uint(-debtorNet)
            : uint(creditorNet);

        require(amount <= maxPayable, "Amount exceeds simplified debt");

        _applySimplifiedUSDCSettlement(groupId, msg.sender, to, amount);

        bool success = usdcToken.transferFrom(msg.sender, to, amount);
        require(success, "USDC transfer failed");
    }
}