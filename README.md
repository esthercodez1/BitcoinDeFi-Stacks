# DeFi Protocol Smart Contract v1.0.0

### **Overview**

This repository contains a Decentralized Finance (DeFi) protocol built on the Bitcoin network via Stacks. The contract enables users to participate in lending, borrowing, and liquidity provision. The smart contract interacts with SIP-010 compliant fungible tokens, allowing seamless integration with existing tokens in the ecosystem. Key functionalities include deposits (liquidity provision), borrowing with collateral, and automatic interest rate adjustments based on the protocol's utilization rate.

---

## **Table of Contents**

- [DeFi Protocol Smart Contract v1.0.0](#defi-protocol-smart-contract-v100) - [**Overview**](#overview)
  - [**Table of Contents**](#table-of-contents)
  - [**Features**](#features)
  - [**Smart Contract Components**](#smart-contract-components)
    - [**Constants**](#constants)
    - [**Data Variables**](#data-variables)
    - [**Data Maps**](#data-maps)
    - [**Private Functions**](#private-functions)
    - [**Public Functions**](#public-functions)
      - [1. **initialize-pool**](#1-initialize-pool)
      - [2. **deposit**](#2-deposit)
      - [3. **borrow**](#3-borrow)
      - [4. **repay**](#4-repay)
    - [**Read-Only Functions**](#read-only-functions)
  - [**Interaction Flow**](#interaction-flow)
  - [**Security Considerations**](#security-considerations)
  - [**Interest Rate Mechanism**](#interest-rate-mechanism)
  - [**Collateralization and Liquidation**](#collateralization-and-liquidation)
  - [**Protocol Fees**](#protocol-fees)
  - [**Deployment \& Setup**](#deployment--setup)
  - [**Usage Examples**](#usage-examples)
    - [Deposit Example](#deposit-example)
    - [Borrow Example](#borrow-example)
    - [Repay Example](#repay-example)
  - [**License**](#license)

---

## **Features**

- **Lending & Borrowing**: Users can deposit tokens as collateral to borrow other tokens.
- **Collateralization**: Borrowers must provide sufficient collateral to secure their loans, ensuring protocol stability.
- **Dynamic Interest Rates**: Interest rates adjust dynamically based on pool utilization, encouraging liquidity provision and balancing supply-demand dynamics.
- **Security Measures**: Built-in validation and safeguards for safe deposit, borrowing, and repayment transactions.
- **Protocol Fee**: A small fee (0.1%) is charged on certain actions to support the long-term sustainability of the protocol.

---

## **Smart Contract Components**

### **Constants**

The protocol defines several constants to manage the core operations. These include error codes, economic parameters like collateral ratios, and protocol fees.

- **`contract-owner`**: The owner of the contract (set to `tx-sender` at deployment).
- **Collateralization Ratios**:
  - **`minimum-collateral-ratio`**: Minimum 150% collateral required to borrow.
  - **`liquidation-threshold`**: A 130% collateral threshold for liquidation.
  - **`liquidation-penalty`**: A 10% bonus for liquidators when loans are liquidated.
- **Protocol Fee**:
  - **`protocol-fee`**: A 0.1% fee charged on certain transactions.

Error codes like `err-owner-only`, `err-not-enough-balance`, `err-insufficient-collateral`, and others are also defined to handle possible contract failures efficiently.

### **Data Variables**

Global variables to track key protocol metrics:

- **`protocol-paused`**: Tracks whether the protocol is paused (default is `false`).
- **`total-value-locked` (TVL)**: Total amount of liquidity deposited in the protocol.
- **`total-borrows`**: The total amount of tokens borrowed across the protocol.
- **`last-price-update`**: Timestamp of the most recent price update in the protocol.

### **Data Maps**

Several `map` data structures are used to store dynamic protocol data:

- **`pools`**: Tracks liquidity pools for each token, including total supply, total borrowed, supply rate, borrow rate, and the last update block.
- **`user-deposits`**: Stores user deposit data for each token (amount deposited and rewards index).
- **`user-borrows`**: Tracks users' borrow amounts, collateral, and the last update time.
- **`price-feeds`**: Stores the price of tokens for collateral and borrowing calculations.

### **Private Functions**

- **`get-minimum(a, b)`**: Returns the smaller of two values.
- **`calculate-interest-rate(total-supply, borrowed-amount)`**: Determines interest rates based on pool utilization.
- **`update-pool-rates(token)`**: Updates interest rates for a given pool based on the current supply and borrow demand.
- **`get-collateral-ratio(borrow-amount, collateral-amount, borrow-token, collateral-token)`**: Calculates the current collateralization ratio for a loan.

### **Public Functions**

#### 1. **initialize-pool**

```clojure
(define-public (initialize-pool (token-contract <ft-trait>)))
```

This function initializes a liquidity pool for a specific SIP-010 token. Only the contract owner can call this function.

#### 2. **deposit**

```clojure
(define-public (deposit (token-contract <ft-trait>) (amount uint)))
```

Allows users to deposit SIP-010 tokens into the protocol and adds liquidity to the corresponding pool.

#### 3. **borrow**

```clojure
(define-public (borrow (borrow-token-contract <ft-trait>) (borrow-amount uint) (collateral-token-contract <ft-trait>) (collateral-amount uint)))
```

Enables users to borrow tokens by depositing collateral. It verifies collateralization ratios before borrowing.

#### 4. **repay**

```clojure
(define-public (repay (token-contract <ft-trait>) (amount uint)))
```

Allows borrowers to repay their loans. The function automatically adjusts the user's borrow and updates the pool's state.

### **Read-Only Functions**

Several read-only functions allow users to view protocol status without changing the contract state:

- **`get-pool-info(token)`**: Retrieves information about a liquidity pool.
- **`get-user-deposits(user, token)`**: Shows the deposits made by a specific user.
- **`get-user-borrows(user, token)`**: Returns details of a user's borrow transactions.
- **`get-protocol-stats()`**: Provides key protocol metrics like TVL, total borrowed, and the last price update.

---

## **Interaction Flow**

1. **Initialize Pool**: The contract owner initializes liquidity pools for each token.
2. **Deposit Liquidity**: Users deposit tokens into the pool and earn interest over time based on the supply rate.
3. **Borrowing**: Users can borrow tokens by depositing collateral, maintaining a sufficient collateralization ratio.
4. **Repay Loans**: Borrowers repay their loans, returning tokens to the pool and unlocking their collateral.
5. **Interest Rate Adjustment**: Rates are dynamically adjusted based on the pool's utilization.

---

## **Security Considerations**

- **Paused Protocol**: The protocol can be paused by the owner for emergencies, preventing further deposits or borrow activity.
- **Collateralization Enforcement**: Borrowers are required to maintain a minimum collateral ratio of 150%, ensuring the protocol is protected against under-collateralized loans.
- **Liquidation Mechanism**: If a borrower's collateral falls below 130%, liquidators can step in to repay loans and claim a portion of the collateral with a 10% liquidation bonus.

---

## **Interest Rate Mechanism**

Interest rates for borrowing and lending are determined by the utilization rate of the pool, which is calculated as:

```clojure
(utilization-rate = (borrowed-amount / total-supply) * 100)
```

- **Base Rate**: 2% (fixed).
- **Utilization Multiplier**: 10%. As utilization increases, the borrow rate increases, encouraging liquidity provision.

---

## **Collateralization and Liquidation**

- **Minimum Collateral Ratio**: 150%. If the collateral provided is less than 150% of the borrowed amount, the transaction is rejected.
- **Liquidation**: If the collateral value drops to 130%, a liquidator can repay the loan and claim the collateral, receiving a 10% bonus.

---

## **Protocol Fees**

- **Protocol Fee**: 0.1% on key transactions like borrowing and repaying, contributing to the protocol’s operational costs.

---

## **Deployment & Setup**

To deploy and initialize the protocol:

1. **Deploy the Smart Contract**: Deploy the contract on the Stacks blockchain, ensuring compatibility with SIP-010 tokens.
2. **Initialize Pools**: The contract owner must initialize liquidity pools for each token by calling `initialize-pool`.
3. **Provide Price Feeds**: Ensure accurate price data for tokens is available in the `price-feeds` map for proper collateral valuation.

---

## **Usage Examples**

### Deposit Example

```clojure
(define-public (deposit (token-contract <ft-trait>) (amount u1000)))
```

### Borrow Example

```clojure
(define-public (borrow (borrow-token-contract <ft-trait>) (borrow-amount u500) (collateral-token-contract <ft-trait>) (collateral-amount u750)))
```

### Repay Example

```clojure
(define-public (repay (token-contract <ft-trait>) (amount u200)))
```

---

## **License**

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
