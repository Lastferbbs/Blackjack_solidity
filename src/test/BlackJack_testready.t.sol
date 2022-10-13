//SPDX-Licence-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

error TooBigBet();
error CantDoubleNow();
error NotMinedYet();
error GameIsOver();
error NotOwner();
error BetMustBeBiggerThan0();
error NotEnoughChips();
error PreviousGameNotFinished();
error GameNotStarted();

contract BlackJack is Test {
    mapping(address => uint256) public currentBet;
    mapping(address => uint256) public currentValuePlayer; // wziac pod uwage karty osobno, do splita
    //mapping(address => uint256) public current_value_dealer;
    mapping(address => uint256) public playerBlock; // first block chosen to generate cards
    mapping(address => uint256) public currentBlock;
    // mapping(address => uint256) public dealer_block;
    // mapping(address => bool) public split_bool;
    mapping(address => uint256) public acesNumber;
    // mapping(address => uint256) public winnings;
    mapping(address => bool) public standStatus;
    mapping(address => bool) public doubleStatus;
    mapping(address => bool) public gameOver;
    mapping(address => uint256) public availableChips; // mozna odejmowac 10 od currentValuePlayer za kazdego asa, do tego odejmowac asa przy > 21
    mapping(address => uint256) public cashInPool;

    uint256 public casinoBalance;
    address owner;

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner();
        }
        _;
    }

    modifier gameFinished() {
        if (standStatus[msg.sender] || gameOver[msg.sender]) {
            revert GameIsOver();
        }

        _;
    }

    modifier settlePlayer() {
        if (standStatus[msg.sender] || gameOver[msg.sender]) {
            (, , bool blackjk) = playerHand();
            (, bool dealersblackjk, ) = dealersHand();

            if (blackjk && dealersblackjk) {
                availableChips[msg.sender] =
                    availableChips[msg.sender] +
                    cashInPool[msg.sender] /
                    2;
                casinoBalance = casinoBalance + cashInPool[msg.sender] / 2;
            } else if (!blackjk && dealersblackjk) {
                casinoBalance = casinoBalance + cashInPool[msg.sender];
            } else if (blackjk && !dealersblackjk) {
                availableChips[msg.sender] =
                    availableChips[msg.sender] +
                    (cashInPool[msg.sender]) +
                    cashInPool[msg.sender] / // ustawic ratio miedzy 2:3 a 5:6
                    4;
                casinoBalance = casinoBalance - cashInPool[msg.sender] / 4;
            } else if (currentValuePlayer[msg.sender] > 21) {
                casinoBalance = casinoBalance + cashInPool[msg.sender];
            } else if (currentValuePlayer[msg.sender] < 22) {
                if (currentValuePlayer[msg.sender] == dealerEndGameHand()) {
                    availableChips[msg.sender] =
                        availableChips[msg.sender] +
                        cashInPool[msg.sender] /
                        2;
                    casinoBalance = casinoBalance + cashInPool[msg.sender] / 2;
                } else if (
                    currentValuePlayer[msg.sender] > dealerEndGameHand() ||
                    dealerEndGameHand() > 21
                ) {
                    availableChips[msg.sender] =
                        availableChips[msg.sender] +
                        cashInPool[msg.sender];
                } else if (
                    currentValuePlayer[msg.sender] < dealerEndGameHand()
                ) {
                    casinoBalance = casinoBalance + cashInPool[msg.sender];
                }
            }
        }
        _;
    }

    modifier cleanOldGame() {
        if (standStatus[msg.sender] || gameOver[msg.sender]) {
            currentBet[msg.sender] = 0;
            currentValuePlayer[msg.sender] = 0; // wziac pod uwage karty osobno, do splita
            playerBlock[msg.sender] = 0; // first block chosen to generate cards
            currentBlock[msg.sender] = 0;
            acesNumber[msg.sender] = 0;
            gameOver[msg.sender] = false;
            standStatus[msg.sender] = false;
            doubleStatus[msg.sender] = false;
            cashInPool[msg.sender] = 0;
        }
        _;
    }

    modifier sumPlayerStartingHand() {
        if (
            currentValuePlayer[msg.sender] == 0 && playerBlock[msg.sender] != 0 // opcja dodawania warunku, ktory sprawdza czy gra zostala zakonczona - obnizy potrzebny gas
        ) {
            // (, bool dealersblackjk, ) = dealersHand();
            // if (dealersblackjk) {
            //     standStatus[msg.sender] = true; // rozwazyc wyjebanie
            // }
            (uint256 value1, uint256 value2, ) = playerHand();
            currentValuePlayer[msg.sender] = value1 + value2;
            if (value1 == 11 && value2 == 11 && acesNumber[msg.sender] == 0) {
                acesNumber[msg.sender] = 2;
            } else if (value1 == 11 && acesNumber[msg.sender] == 0) {
                acesNumber[msg.sender] = 1;
            } else if (value2 == 11 && acesNumber[msg.sender] == 0) {
                acesNumber[msg.sender] = 1;
            }
        }
        _;
    }

    modifier startHandBlackJackCheck() {
        if (currentBlock[msg.sender] == 0 && playerBlock[msg.sender] != 0) {
            (, bool dealersblackjk, ) = dealersHand();
            if (dealersblackjk) {
                standStatus[msg.sender] = true; // rozwazyc wyjebanie
            } else if (currentValuePlayer[msg.sender] == 21) {
                standStatus[msg.sender] = true;
            }
        }
        _;
    }

    modifier blackjack() {
        (, , bool blackjk) = playerHand();
        (, bool dealersblackjk, ) = dealersHand();
        if (blackjk || dealersblackjk) {
            gameOver[msg.sender] = true;
        }
        // remis i zakończenie gry
        // } else if (!blackjk && dealersblackjk) {
        //     gameOver[msg.sender] = true;
        //     // przegrana i zakończenie gry
        // } else if (blackjk && !dealersblackjk) {
        //     gameOver[msg.sender] = true;
        //     // wygrana i zakończenie gry
        // }
        _; //do sprawdzenia, pewnie trzeba bedzie dodac transfery pieniezne juz tutaj
    }

    modifier twentyOneOrAbove21() {
        // gdzie sa sumowe karty w przypadku standa????
        if (
            //blockhash(currentBlock[msg.sender])
            currentHitCard() > 0 &&
            (!standStatus[msg.sender] && !gameOver[msg.sender])
        ) {
            // gdzie sa sumowe karty w przypadku standa????
            //zastanowic sie jaki jest powod by nie uwzgledniac tutaj tez 21
            if (currentValuePlayer[msg.sender] + currentHitCard() > 21) {
                if (
                    currentHitCard() == 11 || acesNumber[msg.sender] > 0
                ) {} else {
                    gameOver[msg.sender] = true;
                    currentValuePlayer[msg.sender] =
                        currentValuePlayer[msg.sender] +
                        currentHitCard();
                    // mozna by to obejść sumując karty w currentValuePlayer
                }
                // dobieranie kart krupiera
                // sprawdzeniie kto wygrał
                // nie zmieniac wartosci asow, jedynie nie zaznaczac przegranej wtedy
            } else if (
                currentValuePlayer[msg.sender] + currentHitCard() == 21 //zastanowic sie czy dodac tutaj blok, zeby zwiekszyc poziom random
            ) {
                // dla kart dealera
                standStatus[msg.sender] = true;
                currentValuePlayer[msg.sender] =
                    currentValuePlayer[msg.sender] +
                    currentHitCard();
                currentBlock[msg.sender] += 1;
            }
        }

        _;
    }

    modifier getDealerCards() {
        _;
        if (standStatus[msg.sender]) {
            currentBlock[msg.sender] = block.number + 1;
        }
    }

    modifier sumCardForDouble() {
        if (doubleStatus[msg.sender]) {
            if (uint256(blockhash(currentBlock[msg.sender])) == 0) {
                revert NotMinedYet();
            } else {
                currentValuePlayer[msg.sender] =
                    currentValuePlayer[msg.sender] +
                    currentHitCard();
                if (currentHitCard() == 11) {
                    acesNumber[msg.sender] += 1;
                }
            }
        }
        _;
    }

    modifier sumNextPlayerCard() {
        if (currentValuePlayer[msg.sender] != 0 && currentHitCard() > 0) {
            //zastanowic sie nad revert
            currentValuePlayer[msg.sender] =
                currentValuePlayer[msg.sender] +
                currentHitCard();
            if (currentHitCard() == 11) {
                acesNumber[msg.sender] += 1;
            }
        }
        _;
    }

    modifier acesCleaning() {
        if (currentValuePlayer[msg.sender] > 21 && acesNumber[msg.sender] > 0) {
            for (uint256 i = 1; i <= acesNumber[msg.sender]; i++) {
                if (currentValuePlayer[msg.sender] - i * 10 < 22) {
                    currentValuePlayer[msg.sender] =
                        currentValuePlayer[msg.sender] -
                        i *
                        10;
                    acesNumber[msg.sender] = acesNumber[msg.sender] - i;
                    break;

                    // uwzglednic asy do standa /////////////////////////////
                }
            }
            // if (currentValuePlayer[msg.sender] > 21) {
            //     gameOver[msg.sender] = true;
            // }
        }
        _;
    }

    ///// CONSTRUCTOR AND FUNCTIONS //////

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    function casinoDeposit() external payable onlyOwner {
        casinoBalance += msg.value;
    }

    function casinoWithdraw(uint256 withdraw_money) external onlyOwner {
        // onlyOwner
        if (withdraw_money <= casinoBalance) {
            casinoBalance -= withdraw_money; //reentrance
            payable(msg.sender).transfer(withdraw_money);
            // transfer
        }
    }

    function buyChips() external payable settlePlayer cleanOldGame {
        if (msg.value > casinoBalance / 10) {
            // pytanie czy jest sens to sprawdzac
            revert TooBigBet();
        }
        availableChips[msg.sender] += msg.value;
    }

    function withdrawMoney(uint256 cash)
        external
        sumPlayerStartingHand
        twentyOneOrAbove21
        settlePlayer
        cleanOldGame
    {
        if (cash <= availableChips[msg.sender]) {
            availableChips[msg.sender] -= cash; //reentrance
            payable(msg.sender).transfer(cash);

            //transfer to msg.sender, zmienic też na call
            // revert TooBigBet();
        } else {
            revert NotEnoughChips();
        }
    } //reetrance guard

    function betWithChips(uint256 bet_size)
        external
        sumPlayerStartingHand
        startHandBlackJackCheck
        sumCardForDouble
        twentyOneOrAbove21
        acesCleaning
        settlePlayer
        cleanOldGame
    {
        if (
            playerBlock[msg.sender] > 0 &&
            (!gameOver[msg.sender]) &&
            !standStatus[msg.sender]
        ) {
            if (blockhash(playerBlock[msg.sender]) == 0) {
                revert PreviousGameNotFinished();
            }
            (, , bool blackjk) = playerHand();
            (, bool dealersblackjk, ) = dealersHand();
            if (blackjk || dealersblackjk) {} else {
                revert PreviousGameNotFinished();
            }
        }
        if (bet_size > availableChips[msg.sender]) {
            revert NotEnoughChips();
        } else if (bet_size <= 0) {
            revert BetMustBeBiggerThan0();
        } else if (bet_size > casinoBalance / 10) {
            revert TooBigBet();
        }
        availableChips[msg.sender] -= bet_size;
        currentBet[msg.sender] = bet_size;
        playerBlock[msg.sender] = block.number + 1;
        cashInPool[msg.sender] = bet_size * 2;
        casinoBalance -= bet_size;
    }

    // function bet() public payable settlePlayer cleanOldGame {
    //     if (msg.value > address(this).balance / 10) {
    //         revert TooBigBet();
    //     }
    //     // uwzglednic minimalny bet
    //     currentBet[msg.sender] = msg.value;
    //     playerBlock[msg.sender] = block.number + 1;
    //     cashInPool[msg.sender] = msg.value * 2;
    //     casinoBalance -= msg.value;
    // }

    ///////////////////////////////GAME PLAY STARTS//////////////////////////////////////////////////////

    function hit()
        public
        blackjack
        sumPlayerStartingHand
        twentyOneOrAbove21
        gameFinished
        sumNextPlayerCard
        acesCleaning
    {
        //uwzglednic ponizsze sumowanie tylko, gdy gra trwa tj. bez stand i gameover

        // if (playerBlock[msg.sender] == 0) {
        //     revert GameNotStarted();
        // } else if (
        if (
            currentBlock[msg.sender] > 0 &&
            uint256(blockhash(currentBlock[msg.sender])) == 0 //mozna to wrzucic na początek i ograniczyć koszt reverta
        ) {
            revert NotMinedYet();
        } else currentBlock[msg.sender] = block.number + 1;
    }

    function stand()
        external
        sumPlayerStartingHand
        blackjack
        twentyOneOrAbove21
        gameFinished
        sumNextPlayerCard
        acesCleaning
        getDealerCards
    {
        // modyfikator, ktory sprawdza czy nie jest powyzej 21!
        if (
            currentBlock[msg.sender] > 0 &&
            uint256(blockhash(currentBlock[msg.sender])) == 0 //mozna to wrzucic na początek i ograniczyć koszt reverta
        ) {
            revert NotMinedYet();
        } else if (playerBlock[msg.sender] == 0) {
            revert GameNotStarted();
        }

        standStatus[msg.sender] = true;
    }

    function double() external payable getDealerCards {
        // uwzglednic brak hita
        (, , bool blackjk) = playerHand();
        (, bool dealersblackjk, ) = dealersHand();
        if (currentBlock[msg.sender] > 0 || (blackjk || dealersblackjk)) {
            revert CantDoubleNow();
        }
        // modyfikator, ktory sprawdza czy double jest dozwolony
        else if (availableChips[msg.sender] < currentBet[msg.sender]) {
            //msg.value != current_bet[msg.sender] || rozwazyc opcje z wplatą hajsu
            revert NotEnoughChips();
        } else {
            casinoBalance -= currentBet[msg.sender];
            availableChips[msg.sender] -= currentBet[msg.sender];
            currentBet[msg.sender] = currentBet[msg.sender] * 2;
            cashInPool[msg.sender] += currentBet[msg.sender]; // zastanowic sie czy nie lepiej wyrownac do wartosci 2xcurrent_bet[msg.sender]
            hit();
            doubleStatus[msg.sender] = true;
            standStatus[msg.sender] = true;
            // end game
        }
    }

    ///////////////////////////////GAME PLAY ENDS//////////////////////////////////////////////////////

    //////////////////////////////HELPER FUNCTIONS//////////////////////////////////////

    function playerHand()
        public
        view
        returns (
            uint256,
            uint256,
            bool
        )
    {
        bytes32 block_nb = blockhash(playerBlock[msg.sender]);
        // if (playerBlock[msg.sender] == 0) {
        //     revert NotMinedYet();
        // } else {
        bool blackjack = false;
        uint256 first_card = 0;
        uint256 second_card = 0;
        first_card = findCard(uint256(block_nb));
        second_card = findCard(
            (uint256(block_nb) / uint256(uint160(msg.sender)))
        );
        if (first_card + second_card == 21) {
            blackjack = true;
        }

        return (first_card, second_card, blackjack); //first_card_player, second_card_player, player_blackjack, first_card_dealer, dealer_blackjack
        // }
    }

    function dealersHand()
        public
        view
        returns (
            uint256,
            bool,
            bool
        )
    {
        bytes32 block_nb = blockhash(playerBlock[msg.sender]);
        if (
            playerBlock[msg.sender] == 0 ||
            (playerBlock[msg.sender] != 0 && block_nb == 0)
        ) {
            revert NotMinedYet();
        } else {
            bool dealerBlackJack = false;
            bool blackjackCheck = false;
            uint256 first_card = findCard(
                uint256(block_nb) / uint256(uint160(address(this)))
            );
            if (first_card == 11) {
                blackjackCheck = true;
                if ((uint256(block_nb) % 10000) < 3097) {
                    dealerBlackJack = true;
                }
            }
            if (first_card == 10) {
                blackjackCheck = true;
                if ((uint256(block_nb) % 10000) < 775) {
                    dealerBlackJack = true;
                }
            }
            return (first_card, dealerBlackJack, blackjackCheck);
            //dodac opcje blackjacka, czyli uwzglednic prawdopodobiestwo wylosowania 10 przy asie(4/13) i asa przy 10(1/13)
        }
    }

    function currentHitCard() public view returns (uint256) {
        if (currentBlock[msg.sender] == 0) {
            return 0;
        }

        uint256 block_nb = uint256(blockhash(currentBlock[msg.sender]));
        // if (currentBlock[msg.sender] == 0) {
        //     revert NotMinedYet();
        // } else {
        block_nb = findCard(block_nb);
        return (block_nb);
        // }
    }

    function restOfDealersCards()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256 ///mozna pomyslec o uwzglednieniu chainlink price feeds
        )
    {
        if (standStatus[msg.sender]) {
            //uwzglednic sytuacje, w ktorej mimo oblanego checka na blackjacka on sie pojawia
            // dodac tez funkcje, ktora zwraca wylosowana karte
            uint256 card1 = findDealersSecondCard(
                uint256(blockhash(currentBlock[msg.sender])) /
                    (uint256(uint160(msg.sender)))
            );
            uint256 card2 = findCard(
                (uint256(blockhash(currentBlock[msg.sender])) /
                    uint256(uint160(address(this))))
            );
            uint256 card3 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 1))
            );
            uint256 card4 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 1)) /
                    uint256(uint160(address(this))))
            );
            uint256 card5 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 2))
            );
            uint256 card6 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 2)) /
                    uint256(uint160(address(this))))
            );
            uint256 card7 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 3))
            );
            uint256 card8 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 3)) /
                    uint256(uint160(address(this))))
            );
            // uint256 card3 = (uint256(blockhash(currentBlock[msg.sender] + 1)) %
            //     9) + 2;
            // uint256 card4 = ((uint256(
            //     blockhash(currentBlock[msg.sender] + 1)
            // ) / uint256(uint160(address(this)))) % 9) + 2;
            // uint256 card5 = (uint256(blockhash(currentBlock[msg.sender] + 2)) %
            //     9) + 2;
            // uint256 card6 = ((uint256(
            //     blockhash(currentBlock[msg.sender] + 2)
            // ) / uint256(uint160(address(this)))) % 9) + 2;
            // uint256 card7 = (uint256(blockhash(currentBlock[msg.sender] + 3)) %
            //     9) + 2;
            // uint256 card8 = ((uint256(
            //     blockhash(currentBlock[msg.sender] + 3)
            // ) / uint256(uint160(address(this)))) % 9) + 2;

            return (card1, card2, card3, card4, card5, card6, card7, card8);
        } else if (currentValuePlayer[msg.sender] + currentHitCard() == 21) {
            //uwzglednic sytuacje, w ktorej mimo oblanego checka na blackjacka on sie pojawia
            // dodac tez funkcje, ktora zwraca wylosowana karte
            uint256 card1 = findDealersSecondCard(
                uint256(blockhash(currentBlock[msg.sender] + 1)) /
                    (uint256(uint160(msg.sender)))
            );
            uint256 card2 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 1)) /
                    uint256(uint160(address(this))))
            );
            uint256 card3 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 2))
            );
            uint256 card4 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 2)) /
                    uint256(uint160(address(this))))
            );
            uint256 card5 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 3))
            );
            uint256 card6 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 3)) /
                    uint256(uint160(address(this))))
            );
            uint256 card7 = findCard(
                uint256(blockhash(currentBlock[msg.sender] + 4))
            );
            uint256 card8 = findCard(
                (uint256(blockhash(currentBlock[msg.sender] + 4)) /
                    uint256(uint160(address(this))))
            );
            return (card1, card2, card3, card4, card5, card6, card7, card8);
        }
    }

    function blockHashCheck() public view returns (uint256) {
        bytes32 blocks = (blockhash(block.number - 1));
        return uint256(blocks);
    }

    function findCard(uint256 number) public pure returns (uint256) {
        if (number == 0) {
            return number;
        } else if ((number % 13) + 1 >= 10) {
            uint256 card = 10;
            return card;
        } else if ((number % 13) + 1 == 1) {
            uint256 card = 11;
            return card;
        } else {
            uint256 card = (number % 13) + 1;
            return card;
        }

        // if (number % 52 > 35) {
        //     uint256 card = 10;
        //     return card;
        // } else {
        //     if (((((number % 52) + 1) % 9) + 1) == 1) {
        //         uint256 card = 11;
        //         return card;
        //     } else {
        //         uint256 card = ((((number % 52) + 1) % 9) + 1);
        //         return card;
        //     }
        // }
    }

    function findDealersSecondCard(
        uint256 number /// uzyc sposobu z 13 kartami i zamiana 11+ na 10
    ) public view returns (uint256) {
        (
            uint256 firstCard,
            bool dealerBlackJack,
            bool blackjackCheck
        ) = dealersHand();
        if (blackjackCheck) {
            if (firstCard == 11 && dealerBlackJack) {
                uint256 card = 10;
                return card;
            } else if (firstCard == 11 && !dealerBlackJack) {
                uint256 card = (number % 9) + 1;
                if (card == 1) {
                    return 11;
                } else {
                    return card;
                }
            } else if (firstCard == 10 && dealerBlackJack) {
                uint256 card = 11;
                return card;
            } else if (firstCard == 10 && !dealerBlackJack) {
                uint256 card = (number % 9) + 2;
                return card;
            }
        } else {
            if (number == 0) {
                //zastanowic sie nad dodaniem revert
                return number;
            } else if ((number % 13) + 1 >= 10) {
                uint256 card = 10;
                return card;
            } else if ((number % 13) + 1 == 1) {
                uint256 card = 11;
                return card;
            } else {
                uint256 card = (number % 13) + 1;
                return card;
            }
        }
    }

    function dealerEndGameHand() public view returns (uint256) {
        (uint256 card1, , ) = dealersHand();
        (
            uint256 card2,
            uint256 card3,
            uint256 card4,
            uint256 card5,
            uint256 card6,
            uint256 card7,
            uint256 card8,
            uint256 card9
        ) = restOfDealersCards();
        uint256[9] memory karty = [
            card1,
            card2,
            card3,
            card4,
            card5,
            card6,
            card7,
            card8,
            card9
        ];
        uint256 aces;
        uint256 sum;
        for (uint256 i = 0; i <= karty.length; i++) {
            if (karty[i] == 0) {
                revert NotMinedYet();
            }
            sum = sum + karty[i];
            if (karty[i] == 11) {
                aces = aces + 1;
            }
            if (sum >= 17 && sum < 22) {
                return sum; //uwzglednic current_value_dealer[msg.sender]
            } else if (sum > 21) {
                if (aces > 0) {
                    sum = sum - 10;
                    aces = aces - 1;
                    if (sum >= 17 && sum < 22) {
                        return sum;
                    } else if (sum > 21 && aces == 0) {
                        return sum;
                    }
                } else {
                    return sum;
                }
                //uwzglednic current_value_dealer[msg.sender]
            }
        }
    }

    function dealerEndGameHandInjected(
        uint256 card1,
        uint256 card2,
        uint256 card3,
        uint256 card4,
        uint256 card5,
        uint256 card6,
        uint256 card7,
        uint256 card8,
        uint256 card9
    ) public view returns (uint256) {
        uint256[9] memory karty = [
            card1,
            card2,
            card3,
            card4,
            card5,
            card6,
            card7,
            card8,
            card9
        ];
        uint256 aces;
        uint256 sum;
        for (uint256 i = 0; i <= karty.length; i++) {
            if (karty[i] == 0) {
                revert NotMinedYet();
            }
            sum = sum + karty[i];
            if (karty[i] == 11) {
                aces = aces + 1;
            }
            if (sum >= 17 && sum < 22) {
                return sum; //uwzglednic current_value_dealer[msg.sender]
            } else if (sum > 21) {
                if (aces > 0) {
                    sum = sum - 10;
                    aces = aces - 1;
                    if (sum >= 17 && sum < 22) {
                        return sum;
                    } else if (sum > 21 && aces == 0) {
                        return sum;
                    }
                } else {
                    return sum;
                }
                //uwzglednic current_value_dealer[msg.sender]
            }
        }
    }

    // function GameStatus(uint256 status) public {
    //     if (status == 0) {
    //         gameOver[msg.sender] = 0;
    //         standStatus[msg.sender] = 0;
    //     } else if (status == 1) {
    //         gameOver[msg.sender] = 1;
    //     }
    // }

    // function setCurrentBlock(uint256 blockNumber) public {
    //     currentBlock[msg.sender] = block.number + 1;
    // }
}

contract BlackJackTest is Test {
    BlackJack blackjack;
    using stdStorage for StdStorage;

    // error TooBigBet();

    receive() external payable {}

    function setUp() public {
        blackjack = new BlackJack();
    }

    function testDepositAndWithdraw(uint96 amount) public {
        blackjack.casinoDeposit{value: amount}();
        assertEq(blackjack.casinoBalance(), amount);
        vm.prank(address(0));
        vm.expectRevert(0x30cd7471);
        uint256 preBalance = address(this).balance;
        blackjack.casinoWithdraw(amount);
        blackjack.casinoWithdraw(amount);
        uint256 postBalance = address(this).balance;
        assertEq(preBalance + amount, postBalance);
    }

    function testBuyChipsAndWithdrawPlayerMoney(uint96 amount) public {
        vm.assume(amount < 999999);
        // troche bez sensu jest ograniczac ilosc zetonow, skoro mozna ograniczyc beta
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 10}();
        uint256 chips = blackjack.availableChips(address(this));
        assertEq(chips, amount / 10);
        uint256 preBalance = address(this).balance;
        blackjack.withdrawMoney(amount / 10);
        uint256 postBalance = address(this).balance;
        assertEq(preBalance + amount / 10, postBalance);
    }

    function testBetWithChips(uint48 amount) public {
        vm.assume(amount > 99999);
        blackjack.casinoDeposit{value: amount}();
        assertEq(blackjack.casinoBalance(), amount);
        // bet without chips - revert
        vm.prank(address(0));
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.betWithChips(amount / 11);
        // bet more than 1/10 of casino balance - revert
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.betWithChips(amount / 9);
        // normal bet - testing variables
        blackjack.buyChips{value: amount / 10}();
        blackjack.buyChips{value: amount / 10}();
        vm.expectRevert(TooBigBet.selector);
        blackjack.betWithChips(amount / 9);
        uint256 prechips = blackjack.availableChips(address(this));
        uint256 preCasinoBalance = blackjack.casinoBalance();
        blackjack.betWithChips(amount / 10);
        uint256 postchips = blackjack.availableChips(address(this));
        assertEq(prechips - amount / 10, postchips);
        assertEq(blackjack.currentBet(address(this)), amount / 10);
        uint256 currentBlock = block.number;
        assertEq(currentBlock + 1, blackjack.playerBlock(address(this)));
        assertEq((amount / 10) * 2, blackjack.cashInPool(address(this)));
        assertEq(preCasinoBalance - amount / 10, blackjack.casinoBalance());
        // wziac pod uwage modifiers
    }

    function testHelperFunctions(uint256 number) public {
        ///// FIND CARD ////
        number = bound(number, 257, 100000000);

        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 10}();
        blackjack.betWithChips(amount / 10);

        vm.roll(number + 2);
        uint256 card = blackjack.findCard(cards);
        uint256 real_card = 0;
        if (cards == 13) {
            real_card = 11;
        } else if (cards >= 9) {
            real_card = 10;
        } else if (cards > 0 && cards < 9) {
            real_card = cards + 1;
        } else {
            real_card = 0;
        }
        assertEq(real_card, card);
        // uint256 hash_int = uint256(blockhash(block.number - 1));
        // assertEq(hash_int, 2);

        /////// Player's hand ////

        (uint256 card1, uint256 card2, bool blackjack_bool) = blackjack
            .playerHand();
        console.log(card1, card2);

        if (card1 + card2 == 21) {
            assertEq(true, blackjack_bool);
        }
        /////// Dealer's hand //////

        uint256 dBlock = uint256(blackjack.playerBlock(address(this)));
        card = blackjack.findCard(
            uint256(blockhash(dBlock)) / uint256(uint160(address(blackjack)))
        );
        (uint256 dCard1, bool dealerBlackJack, bool blackjackCheck) = blackjack
            .dealersHand();
        assertEq(card, dCard1);
        if (card == 11 || card == 10) {
            assertEq(true, blackjackCheck);
        }

        /////// Find Dealer's Second Card ////////   --- zastanowić się czy karta równa zero może gdzieś przejść - raczej nie, moze wyjdzie w T
        /// test prawidlowych kart przy blackjacku i blackjackchecku
        /// test losowych kart przy braku blackjacka
        if (!blackjack_bool && !dealerBlackJack) {
            blackjack.hit();
            vm.roll(number + 4);
            uint256 secondDCard = blackjack.findDealersSecondCard(
                uint256(blockhash(blackjack.currentBlock(address(this))))
            );
            uint256 rightSecondCard = (uint256(
                blockhash(blackjack.currentBlock(address(this)))
            ) % 9);
            // if (!dealerBlackJack && blackjackCheck) {
            //     if (dCard1 == 11) {
            //         rightSecondCard = rightSecondCard + 1;
            //         if (rightSecondCard == 1) {
            //             rightSecondCard = 11;
            //         }
            //         assertEq(secondDCard, rightSecondCard);
            //     } else if (dCard1 == 10) {
            //         rightSecondCard = rightSecondCard + 2;
            //         assertEq(secondDCard, rightSecondCard);
            //     }
            // }
            if (rightSecondCard == 1) {
                rightSecondCard = 11;
            }
            // if (dealerBlackJack) {
            //     if (dCard1 == 11) {
            //         assertEq(secondDCard, 10);
            //     } else if (dCard1 == 10) {
            //         assertEq(secondDCard, 11);
            //     }
            // }

            //// Dealer's End Game Hand ///////

            uint256 sum = blackjack.dealerEndGameHandInjected(
                11,
                11,
                11,
                9,
                10,
                11,
                2,
                2,
                2
            );
            assertEq(sum, 22);
            sum = blackjack.dealerEndGameHandInjected(
                11,
                11,
                9,
                11,
                10,
                2,
                2,
                2,
                2
            );
            assertEq(sum, 21);
            sum = blackjack.dealerEndGameHandInjected(
                10,
                7,
                9,
                11,
                10,
                2,
                2,
                2,
                2
            );
            assertEq(sum, 17);
            sum = blackjack.dealerEndGameHandInjected(
                9,
                9,
                9,
                11,
                10,
                2,
                2,
                2,
                2
            );
            assertEq(sum, 18);
            sum = blackjack.dealerEndGameHandInjected(
                9,
                7,
                9,
                11,
                10,
                2,
                2,
                2,
                2
            );
            assertEq(sum, 25);
        }
    }

    function testHitFunctionAndModifiers(uint256 number) public {
        number = bound(number, 257, 100000000);

        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 10}();
        blackjack.betWithChips(amount / 10);

        vm.roll(number + 2);
        // stdstore
        //     .target(address(blackjack))
        //     .sig("gameOver(address)")
        //     .with_key(address(this))
        //     .checked_write(true);
        // vm.expectRevert(GameIsOver.selector);
        // blackjack.hit();

        // stdstore
        //     .target(address(blackjack))
        //     .sig("gameOver(address)")
        //     .with_key(address(this))
        //     .checked_write(false);
        // stdstore
        //     .target(address(blackjack))
        //     .sig("standStatus(address)")
        //     .with_key(address(this))
        //     .checked_write(true);
        // vm.expectRevert(GameIsOver.selector);
        // blackjack.hit();
        // stdstore
        //     .target(address(blackjack))
        //     .sig("standStatus(address)")
        //     .with_key(address(this))
        //     .checked_write(false);
        assertEq(blackjack.currentBlock(address(this)), 0);
        assertEq(blackjack.currentValuePlayer(address(this)), 0);
        //assertEq(blackjack.playerBlock(address(this)), 1);
        assertEq(blackjack.acesNumber(address(this)), 0);

        (uint256 card1, uint256 card2, bool black) = blackjack.playerHand();
        // if (black) {
        //     assertEq(false, blackjack.gameOver(address(this)));
        // } else if (card1 + card2 == 22) {
        //     assertEq(1, blackjack.acesNumber(address(this)));
        //     assertEq(12, blackjack.currentValuePlayer(address(this)));
        // } else if (card1 == 11 && card2 != 11) {
        //     assertEq(blackjack.acesNumber(address(this)), 1);
        // } else if (card2 == 11 && card1 != 11) {
        //     assertEq(blackjack.acesNumber(address(this)), 1);
        // }
        // stdstore
        //     .target(address(blackjack))
        //     .sig("currentValuePlayer(address)")
        //     .with_key(address(this))
        //     .checked_write(20);
        // stdstore
        //     .target(address(blackjack))
        //     .sig("acesNumber(address)")
        //     .with_key(address(this))
        //     .checked_write(1);
        // uint256 nextCard = blackjack.currentHitCard();
        (, bool dealerblackjk, ) = blackjack.dealersHand();

        if (!dealerblackjk && !black) {
            blackjack.hit();
            vm.roll(number + 4);
            uint256 nextCard = blackjack.currentHitCard();
            if (nextCard + card1 + card2 > 21) {
                if (nextCard == 11 || card1 == 11 || card2 == 11) {
                    assertEq(blackjack.gameOver(address(this)), false);
                } else {
                    assertEq(blackjack.gameOver(address(this)), false);
                }
            } else if (nextCard + card1 + card2 == 21) {
                assertEq(blackjack.standStatus(address(this)), false);
            } else {
                assertEq(blackjack.gameOver(address(this)), false);
            }

            // assertEq(
            //     blackjack.currentValuePlayer(address(this)),
            //     10 + nextCard
            // );
            // if (nextCard == 11) {
            //     assertEq(blackjack.acesNumber(address(this)), 1);
            // } else {
            //     assertEq(blackjack.acesNumber(address(this)), 0);
            // }
        } else {
            assertEq(blackjack.gameOver(address(this)), false);
        }
    }

    function testStandFunctionAndModifiers(uint256 number) public {
        number = bound(number, 257, 100000000);

        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 12}();
        blackjack.betWithChips(amount / 12);

        vm.roll(number + 2);
        (uint256 card1, uint256 card2, bool black) = blackjack.playerHand();
        (, bool dealerblackjk, ) = blackjack.dealersHand();
        if (
            card1 + card2 > 3 && card1 + card2 != 22 && !black && !dealerblackjk
        ) {
            blackjack.stand();
        } else if (black || dealerblackjk) {
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
        } else if (card1 + card2 == 21) {
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
        }
        vm.deal(address(1), 2 ether);
        vm.startPrank(address(1));

        blackjack.buyChips{value: amount / 12}();
        assertEq(blackjack.availableChips(address(1)), amount / 12);
        blackjack.betWithChips(amount / 12);

        vm.roll(number + 6);
        (, dealerblackjk, ) = blackjack.dealersHand();
        (card1, card2, black) = blackjack.playerHand();
        if (card1 + card2 != 21 && !dealerblackjk) {
            blackjack.hit();
            vm.expectRevert(NotMinedYet.selector);
            blackjack.stand();
            vm.roll(number + 8);
            if (card1 + card2 + blackjack.currentHitCard() < 21) {
                blackjack.stand();
            } else if (
                card1 + card2 + blackjack.currentHitCard() > 21 &&
                blackjack.acesNumber(address(1)) != 0 &&
                card1 != 11
            ) {
                blackjack.stand();
            } else if (
                card1 + card2 + blackjack.currentHitCard() > 21 &&
                blackjack.currentHitCard() == 11
            ) {
                blackjack.stand();
            } else if (black || dealerblackjk) {
                vm.expectRevert(GameIsOver.selector);
                blackjack.stand();
            } else if (card1 + card2 + blackjack.currentHitCard() == 21) {
                vm.expectRevert(GameIsOver.selector);
                blackjack.stand();
            } else if (
                card1 + card2 + blackjack.currentHitCard() > 21 &&
                blackjack.acesNumber(address(1)) == 0 &&
                blackjack.currentHitCard() != 11
            ) {
                vm.expectRevert(GameIsOver.selector);
                blackjack.stand();
            }

            // blackjack.hit();
            // vm.expectRevert(NotMinedYet.selector);
            // blackjack.stand();
        }
    }

    // function testDoubleFunctionAndModifiers(uint256 number) public {
    //     number = bound(number, 1, 100000000);

    //     uint256 cards = bound(number, 0, 13);
    //     uint256 amount = 1 ether;
    //     vm.roll(number);
    //     blackjack.casinoDeposit{value: amount}();
    //     blackjack.buyChips{value: amount / 10}();
    //     blackjack.betWithChips(amount / 20);
    //     vm.expectRevert(NotMinedYet.selector);
    //     blackjack.double();
    //     vm.roll(number + 2);
    //     (, bool dealerblackjk, ) = blackjack.dealersHand();
    //     (, , bool black) = blackjack.playerHand();
    //     if (!dealerblackjk && !black) {
    //         blackjack.hit();
    //         vm.expectRevert(CantDoubleNow.selector);
    //         blackjack.double();
    //     }
    //     //vm.expectRevert(NotEnoughChips.selector);
    //     //blackjack.double();
    //     //blackjack.buyChips{value: amount / 20}();
    //     else {
    //         blackjack.double();
    //         vm.expectRevert(GameIsOver.selector);
    //         blackjack.stand();
    //         vm.expectRevert(GameIsOver.selector);
    //         blackjack.hit();
    //     }
    // }

    function testEndGameAndModifiers(uint256 number) public {
        number = bound(number, 257, 100000000);
        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 10}();
        blackjack.betWithChips(amount / 20);
        vm.expectRevert(NotMinedYet.selector);
        blackjack.betWithChips(amount / 20);
        vm.roll(number + 2);
        (, bool dealerblackjk, ) = blackjack.dealersHand();
        (uint256 card1, uint256 card2, bool black) = blackjack.playerHand();
        if (dealerblackjk || black) {
            assertEq(blackjack.availableChips(address(this)), amount / 20);
            blackjack.betWithChips(amount / 20);
            if (dealerblackjk && black) {
                assertEq(blackjack.availableChips(address(this)), amount / 20);
            } else if (dealerblackjk) {
                assertEq(blackjack.availableChips(address(this)), 0);
            } else {
                assertEq(
                    blackjack.availableChips(address(this)), //uwzglednic blackjacki w rozdaniu bez dodatkowych transakcji
                    2 * (amount / 20) + amount / 40
                );
            }
        } else {
            blackjack.hit();
            vm.expectRevert(PreviousGameNotFinished.selector);
            blackjack.betWithChips(amount / 20);
            vm.roll(number + 4);
            uint256 playerFinalHand;
            console.logUint(blackjack.currentBlock(address(this)));
            //assertEq(blackjack.currentValuePlayer(address(this)), 22);
            if (
                // POWYZEJ 21
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() >
                21 &&
                blackjack.currentHitCard() != 11 &&
                blackjack.acesNumber(address(this)) == 0
            ) {
                //blackjack.stand();
                blackjack.betWithChips(amount / 20);
                assertEq(blackjack.availableChips(address(this)), 0);
            } else if (
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() ==
                21
            ) {
                // 21 Z TRZECIĄ KARTĄ
                vm.roll(number + 10);
                if (
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() >
                    blackjack.dealerEndGameHand()
                ) {
                    console.logUint(blackjack.currentBlock(address(this)));

                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (blackjack.dealerEndGameHand() > 21) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() ==
                    blackjack.dealerEndGameHand()
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 20
                    );
                } else {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                }
            } else if (
                // PONIZEJ 21
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() <
                21 ||
                (blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() >
                    21 &&
                    (blackjack.acesNumber(address(this)) != 0 ||
                        blackjack.currentHitCard() == 11))
            ) {
                blackjack.stand();
                vm.roll(number + 10);
                if (
                    // WYGRANA KARTAMI
                    blackjack.currentValuePlayer(address(this)) >
                    blackjack.dealerEndGameHand()
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (
                    //PRZEGRANA KARTAMI
                    blackjack.currentValuePlayer(address(this)) <
                    blackjack.dealerEndGameHand() &&
                    blackjack.dealerEndGameHand() < 22
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(blackjack.availableChips(address(this)), 0);
                } else if (blackjack.dealerEndGameHand() > 21) {
                    //WYGRANA, DEALER POWYZEJ 21
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (
                    //REMIS
                    blackjack.dealerEndGameHand() ==
                    blackjack.currentValuePlayer(address(this))
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 20
                    );
                }
            } // PRZETESTOWAĆ JESZCZE DOUBLE!!!!!!!!!!!!!!!!!!!!!!! ORAZ CLEANOLDGAME!!!!!!!!!!!!!! ZASTANOWIC SIE NAD ZMIANA W PLAYERHAND!!!!!
            // PRZEJRZEĆ RESZTĘ FUNKCJI
            // }
            // if (blackjack.availableChips(address(this)) < amount / 20) {
            //     blackjack.buyChips{value: amount / 20}();
            // }
            // vm.roll(number + 13);
            // blackjack.double();
            // vm.roll(number + 16);
            // //assertEq(blackjack.currentValuePlayer(address(this)), 22);
            // if (
            //     // POWYZEJ 21
            //     blackjack.currentValuePlayer(address(this)) +
            //         blackjack.currentHitCard() >
            //     21 &&
            //     blackjack.currentHitCard() != 11 &&
            //     blackjack.acesNumber(address(this)) == 0
            // ) {
            //     //blackjack.stand();
            //     blackjack.buyChips{value: amount / 20}();
            //     blackjack.betWithChips(amount / 20);
            //     assertEq(blackjack.availableChips(address(this)), 0);
            //     // } else if (
            //     //     blackjack.currentValuePlayer(address(this)) +
            //     //         blackjack.currentHitCard() ==
            //     //     21
            //     // ) {
            // }
        }
    }

    function testDoubleAndModifiers(uint256 number) public {
        number = bound(number, 257, 100000000);
        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();
        blackjack.buyChips{value: amount / 10}();
        blackjack.betWithChips(amount / 40);
        vm.roll(number + 2);
        (, bool dealerblackjk, ) = blackjack.dealersHand();
        (uint256 card1, uint256 card2, bool black) = blackjack.playerHand();
        if ((!black && !dealerblackjk)) {
            blackjack.double();
            vm.roll(number + 10);
            if (
                // POWYZEJ 21
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() >
                21 &&
                blackjack.currentHitCard() != 11 &&
                blackjack.acesNumber(address(this)) == 0
            ) {
                //blackjack.stand();
                blackjack.betWithChips(amount / 20);
                assertEq(blackjack.availableChips(address(this)), 0);
            } else if (
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() ==
                21
            ) {
                // 21 Z TRZECIĄ KARTĄ
                if (
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() >
                    blackjack.dealerEndGameHand()
                ) {
                    console.logUint(blackjack.currentBlock(address(this)));

                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (blackjack.dealerEndGameHand() > 21) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() ==
                    blackjack.dealerEndGameHand()
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 20
                    );
                } else {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                }
            } else if (
                // PONIZEJ 21
                blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() <
                21 ||
                (blackjack.currentValuePlayer(address(this)) +
                    blackjack.currentHitCard() >
                    21 &&
                    (blackjack.acesNumber(address(this)) != 0 ||
                        blackjack.currentHitCard() == 11))
            ) {
                if (
                    // WYGRANA KARTAMI -- uwzglednic asy
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() >
                    blackjack.dealerEndGameHand()
                ) {
                    if (
                        // POWYZEJ 21
                        blackjack.currentValuePlayer(address(this)) +
                            blackjack.currentHitCard() >
                        21 &&
                        blackjack.currentHitCard() != 11 &&
                        blackjack.acesNumber(address(this)) == 0
                    ) {
                        //blackjack.stand();
                        blackjack.betWithChips(amount / 20);
                        assertEq(blackjack.availableChips(address(this)), 0);
                        // blackjack.betWithChips(amount / 20);
                        // assertEq(
                        //     blackjack.availableChips(address(this)),
                        //     amount / 10
                        // );
                    } else if (
                        // POWYZEJ 21
                        blackjack.currentValuePlayer(address(this)) +
                            blackjack.currentHitCard() >
                        21 &&
                        (blackjack.currentHitCard() == 11 ||
                            blackjack.acesNumber(address(this)) != 0)
                    ) {
                        if (
                            (blackjack.currentValuePlayer(address(this)) +
                                blackjack.currentHitCard() -
                                10 >
                                blackjack.dealerEndGameHand()) ||
                            blackjack.dealerEndGameHand() > 21
                        ) {
                            blackjack.betWithChips(amount / 20);
                            assertEq(
                                blackjack.availableChips(address(this)),
                                amount / 10
                            );
                        } else if (
                            blackjack.currentValuePlayer(address(this)) +
                                blackjack.currentHitCard() -
                                10 ==
                            blackjack.dealerEndGameHand()
                        ) {
                            blackjack.betWithChips(amount / 20);
                            assertEq(
                                blackjack.availableChips(address(this)),
                                amount / 20
                            );
                        } else if (
                            blackjack.currentValuePlayer(address(this)) +
                                blackjack.currentHitCard() -
                                10 <
                            blackjack.dealerEndGameHand()
                        ) {
                            blackjack.betWithChips(amount / 20);
                            assertEq(
                                blackjack.availableChips(address(this)),
                                0
                            );
                        }
                    } else if (
                        blackjack.currentValuePlayer(address(this)) +
                            blackjack.currentHitCard() <
                        22 &&
                        blackjack.currentValuePlayer(address(this)) +
                            blackjack.currentHitCard() >
                        blackjack.dealerEndGameHand()
                    ) {
                        blackjack.betWithChips(amount / 20);
                        assertEq(
                            blackjack.availableChips(address(this)),
                            amount / 10
                        );
                    }
                } else if (
                    //PRZEGRANA KARTAMI
                    blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard() <
                    blackjack.dealerEndGameHand() &&
                    blackjack.dealerEndGameHand() < 22
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(blackjack.availableChips(address(this)), 0);
                } else if (blackjack.dealerEndGameHand() > 21) {
                    //WYGRANA, DEALER POWYZEJ 21
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 10
                    );
                } else if (
                    //REMIS
                    blackjack.dealerEndGameHand() ==
                    (blackjack.currentValuePlayer(address(this)) +
                        blackjack.currentHitCard())
                ) {
                    blackjack.betWithChips(amount / 20);
                    assertEq(
                        blackjack.availableChips(address(this)),
                        amount / 20
                    );
                }
            }
        } else if (card1 + card2 == 21) {
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
        } else if (dealerblackjk) {
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
        }
        // if (!black && !dealerblackjk) {
        //     vm.expectRevert(NotMinedYet.selector);
        //     blackjack.stand();
        // } else {
        //     vm.expectRevert(GameIsOver.selector);
        //     blackjack.stand();
        // }
        // if (!black && !dealerblackjk) {
        //     vm.expectRevert(NotMinedYet.selector);
        //     blackjack.hit();
        // } else {
        //     vm.expectRevert(GameIsOver.selector);
        //     blackjack.hit();
        // }
        vm.roll(number + 12);
        (, dealerblackjk, ) = blackjack.dealersHand();
        (card1, card2, black) = blackjack.playerHand();
        if (
            (!black && !dealerblackjk) &&
            blackjack.availableChips(address(this)) >= amount / 20
        ) {
            assertEq(blackjack.currentBlock(address(this)), 0);
            blackjack.double();
            // blackjack.hit();
        }
    }

    function testIntegrations(uint256 number) public {
        number = bound(number, 257, 100000000);
        uint256 cards = bound(number, 0, 13);
        uint256 amount = 1 ether;
        vm.roll(number);
        blackjack.casinoDeposit{value: amount}();

        // testing betting without buying chips
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.betWithChips(amount / 5);
        blackjack.buyChips{value: amount / 10}();
        // testing playing without betting
        assertEq(blackjack.playerBlock(address(this)), 0);
        vm.expectRevert(NotMinedYet.selector);
        blackjack.hit();
        vm.expectRevert(NotMinedYet.selector);
        blackjack.stand();
        vm.expectRevert(NotMinedYet.selector);
        blackjack.double();
        // testing withdrawing without buying chips - on different account
        vm.deal(address(123), 2 ether);
        vm.startPrank(address(123));
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.withdrawMoney(amount / 5);
        assertEq(blackjack.availableChips(address(123)), 0);
        // testing withdrawing more than buyed
        blackjack.buyChips{value: amount / 10}();
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.withdrawMoney(amount / 5);
        // testing withdrawing in parts
        blackjack.withdrawMoney(amount / 20);
        assertEq(blackjack.availableChips(address(123)), amount / 20);
        blackjack.withdrawMoney(amount / 20);
        assertEq(blackjack.availableChips(address(123)), 0);
        blackjack.buyChips{value: amount / 10}();
        // testing betting more than available
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.betWithChips(amount / 5);
        blackjack.betWithChips(amount / 40);
        // testing withdrawing all chips after betting
        vm.expectRevert(NotEnoughChips.selector);
        blackjack.withdrawMoney(amount / 10);
        // testing withdrawing part of left chips
        blackjack.withdrawMoney(amount / 20);
        // testing betting after first bet and before finishing game - in the same block
        vm.expectRevert(NotMinedYet.selector);
        blackjack.betWithChips(amount / 40);
        // testing betting after first bet and before finishing game - after playerHand reveal
        vm.roll(number + 2);
        (, bool dealerblackjk, ) = blackjack.dealersHand();
        (uint256 card1, uint256 card2, bool black) = blackjack.playerHand();
        if (!dealerblackjk && !black) {
            vm.expectRevert(PreviousGameNotFinished.selector);
            blackjack.betWithChips(amount / 40);
        } else {
            blackjack.betWithChips(amount / 40);
            vm.roll(number + 4);
            (, dealerblackjk, ) = blackjack.dealersHand();
            (card1, card2, black) = blackjack.playerHand();
            // testing hit, stand and double when blackjack on board
            if (dealerblackjk || black) {
                vm.expectRevert(GameIsOver.selector);
                blackjack.hit();
                vm.expectRevert(GameIsOver.selector);
                blackjack.stand();
                vm.expectRevert(CantDoubleNow.selector);
                blackjack.double();
            } else {
                // testing hit after betting
                blackjack.hit();
                vm.roll(number + 6);
                if (
                    // testing hit when not yet 21 or above + checking if double and stand are unavailable
                    card1 + card2 + blackjack.currentHitCard() < 21 ||
                    ((blackjack.currentHitCard() == 11 ||
                        card1 == 11 ||
                        card2 == 11) &&
                        card1 + card2 + blackjack.currentHitCard() != 21)
                ) {
                    vm.expectRevert(CantDoubleNow.selector);
                    blackjack.double();
                    vm.expectRevert(PreviousGameNotFinished.selector);
                    blackjack.betWithChips(amount / 40);
                    blackjack.stand(); // blackjack.hit()
                    vm.roll(number + 12);
                    if (blackjack.availableChips(address(123)) >= amount / 80) {
                        blackjack.betWithChips(amount / 80);
                    }
                } else if (
                    // testing if hit is not available when sum is above 21, also testing if double and stand are unavailable
                    blackjack.currentHitCard() != 11 &&
                    blackjack.acesNumber(address(123)) == 0
                ) {
                    vm.expectRevert(GameIsOver.selector);
                    blackjack.hit();
                    vm.expectRevert(GameIsOver.selector);
                    blackjack.stand();
                    vm.expectRevert(CantDoubleNow.selector);
                    blackjack.double();
                } else {
                    vm.expectRevert(GameIsOver.selector);
                    blackjack.hit();
                }
            }
        }
        // testing stand after bet
        vm.stopPrank();
        vm.deal(address(321), 2 ether);
        vm.startPrank(address(321));
        blackjack.buyChips{value: amount / 20}();
        blackjack.betWithChips(amount / 80);
        vm.roll(number + 14);
        (, dealerblackjk, ) = blackjack.dealersHand();
        (card1, card2, black) = blackjack.playerHand();

        // testing hit, stand and double when blackjack on board
        if (dealerblackjk || black) {
            vm.expectRevert(GameIsOver.selector);
            blackjack.hit();
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
        } else {
            // testing hit after betting
            blackjack.stand();
            vm.roll(number + 20);
            vm.expectRevert(GameIsOver.selector);
            blackjack.hit();
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
            blackjack.betWithChips(amount / 80);
        }
        vm.stopPrank();
        vm.deal(address(543), 2 ether);
        vm.startPrank(address(543));
        blackjack.buyChips{value: amount / 20}();
        blackjack.betWithChips(amount / 80);
        vm.roll(number + 22);
        (, dealerblackjk, ) = blackjack.dealersHand();
        (card1, card2, black) = blackjack.playerHand();

        // testing hit, stand and double when blackjack on board
        if (dealerblackjk || black) {
            vm.expectRevert(GameIsOver.selector);
            blackjack.hit();
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
        } else {
            // testing hit after betting
            blackjack.double();
            vm.roll(number + 27);
            vm.expectRevert(GameIsOver.selector);
            blackjack.hit();
            vm.expectRevert(GameIsOver.selector);
            blackjack.stand();
            vm.expectRevert(CantDoubleNow.selector);
            blackjack.double();
            blackjack.betWithChips(amount / 80);
        }
    }
}
