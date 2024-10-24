;; DeFi Protocol Smart Contract
;; Version: 1.0.0
;; Description: A DeFi protocol enabling lending, borrowing, and liquidity provision on Bitcoin through Stacks

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-enough-balance (err u101))
(define-constant err-pool-not-found (err u102))
(define-constant err-insufficient-collateral (err u103))
(define-constant err-already-initialized (err u104))
(define-constant err-not-initialized (err u105))
(define-constant err-invalid-amount (err u106))
(define-constant minimum-collateral-ratio u150) ;; 150% collateralization ratio
(define-constant liquidation-threshold u130) ;; 130% threshold for liquidation
(define-constant liquidation-penalty u110) ;; 110% - liquidator gets 10% bonus
(define-constant protocol-fee u10) ;; 0.1% fee (basis points)

;; Data Variables
(define-data-var protocol-paused bool false)
(define-data-var total-value-locked uint u0)
(define-data-var total-borrowed uint u0)
(define-data-var last-price-update uint u0)

;; Data Maps
(define-map pools 
    principal 
    {
        total-supply: uint,
        total-borrowed: uint,
        supply-rate: uint,
        borrow-rate: uint,
        last-update-block: uint
    }
)

(define-map user-deposits 
    { user: principal, token: principal } 
    {
        amount: uint,
        rewards-index: uint
    }
)

(define-map user-borrows
    { user: principal, token: principal }
    {
        amount: uint,
        collateral: uint,
        last-update: uint
    }
)

(define-map price-feeds principal uint)

;; Private Functions
(define-private (calculate-interest-rate (total-supply uint) (total-borrowed uint))
    (let (
        (utilization-rate (if (is-eq total-supply u0)
            u0
            (/ (* total-borrowed u10000) total-supply)))
        (base-rate u200) ;; 2% base rate
        (multiplier u1000) ;; 10% multiplier
    )
    (+ base-rate (* utilization-rate multiplier)))
)

(define-private (update-pool-rates (token principal))
    (let (
        (pool (unwrap! (map-get? pools token) err-pool-not-found))
        (new-borrow-rate (calculate-interest-rate 
            (get total-supply pool)
            (get total-borrowed pool)))
        (new-supply-rate (/ (* new-borrow-rate 
            (get total-borrowed pool))
            (get total-supply pool)))
    )
    (map-set pools token
        (merge pool {
            borrow-rate: new-borrow-rate,
            supply-rate: new-supply-rate,
            last-update-block: block-height
        }))
    (ok true))
)

(define-private (get-collateral-ratio 
    (borrow-amount uint) 
    (collateral-amount uint) 
    (borrow-token principal)
    (collateral-token principal))
    (let (
        (borrow-value (* borrow-amount 
            (unwrap! (map-get? price-feeds borrow-token) err-pool-not-found)))
        (collateral-value (* collateral-amount 
            (unwrap! (map-get? price-feeds collateral-token) err-pool-not-found)))
    )
    (/ (* collateral-value u100) borrow-value))
)

;; Public Functions
(define-public (initialize-pool (token principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (is-none (map-get? pools token)) err-already-initialized)
        (map-set pools token {
            total-supply: u0,
            total-borrowed: u0,
            supply-rate: u0,
            borrow-rate: u200, ;; 2% initial rate
            last-update-block: block-height
        })
        (ok true))
)

(define-public (deposit (token principal) (amount uint))
    (let (
        (pool (unwrap! (map-get? pools token) err-pool-not-found))
        (sender-balance (unwrap! (contract-call? .token get-balance tx-sender) err-not-enough-balance))
    )
    (asserts! (>= sender-balance amount) err-not-enough-balance)
    (asserts! (not (var-get protocol-paused)) err-not-initialized)
    
    ;; Transfer tokens to protocol
    (try! (contract-call? .token transfer amount tx-sender (as-contract tx-sender)))
    
    ;; Update pool state
    (map-set pools token
        (merge pool {
            total-supply: (+ (get total-supply pool) amount),
            last-update-block: block-height
        }))
    
    ;; Update user deposits
    (map-set user-deposits 
        { user: tx-sender, token: token }
        {
            amount: (+ amount
                (default-to u0 
                    (get amount (map-get? user-deposits 
                        { user: tx-sender, token: token })))),
            rewards-index: block-height
        })
    
    ;; Update protocol stats
    (var-set total-value-locked (+ (var-get total-value-locked) amount))
    
    (ok true))
)

(define-public (borrow 
    (borrow-token principal)
    (borrow-amount uint)
    (collateral-token principal)
    (collateral-amount uint))
    (let (
        (pool (unwrap! (map-get? pools borrow-token) err-pool-not-found))
        (collateral-balance (unwrap! 
            (contract-call? .token get-balance tx-sender) 
            err-not-enough-balance))
    )
    (asserts! (>= collateral-balance collateral-amount) err-not-enough-balance)
    (asserts! (not (var-get protocol-paused)) err-not-initialized)
    
    ;; Check collateralization ratio
    (asserts! (>= (get-collateral-ratio 
        borrow-amount
        collateral-amount
        borrow-token
        collateral-token)
        minimum-collateral-ratio)
        err-insufficient-collateral)
    
    ;; Transfer collateral to protocol
    (try! (contract-call? .token transfer 
        collateral-amount
        tx-sender
        (as-contract tx-sender)))
    
    ;; Update pool state
    (map-set pools borrow-token
        (merge pool {
            total-borrowed: (+ (get total-borrowed pool) borrow-amount),
            last-update-block: block-height
        }))
    
    ;; Update user borrows
    (map-set user-borrows
        { user: tx-sender, token: borrow-token }
        {
            amount: (+ borrow-amount
                (default-to u0 
                    (get amount (map-get? user-borrows
                        { user: tx-sender, token: borrow-token })))),
            collateral: collateral-amount,
            last-update: block-height
        })
    
    ;; Transfer borrowed tokens to user
    (try! (contract-call? .token transfer
        borrow-amount
        (as-contract tx-sender)
        tx-sender))
    
    ;; Update protocol stats
    (var-set total-borrowed (+ (var-get total-borrowed) borrow-amount))
    
    (ok true))
)

(define-public (repay (token principal) (amount uint))
    (let (
        (pool (unwrap! (map-get? pools token) err-pool-not-found))
        (borrow-info (unwrap! (map-get? user-borrows
            { user: tx-sender, token: token })
            err-not-enough-balance))
        (repay-amount (min amount (get amount borrow-info)))
    )
    (asserts! (not (var-get protocol-paused)) err-not-initialized)
    
    ;; Transfer repayment to protocol
    (try! (contract-call? .token transfer
        repay-amount
        tx-sender
        (as-contract tx-sender)))
    
    ;; Update pool state
    (map-set pools token
        (merge pool {
            total-borrowed: (- (get total-borrowed pool) repay-amount),
            last-update-block: block-height
        }))
    
    ;; Update user borrows
    (map-set user-borrows
        { user: tx-sender, token: token }
        (merge borrow-info {
            amount: (- (get amount borrow-info) repay-amount),
            last-update: block-height
        }))
    
    ;; Update protocol stats
    (var-set total-borrowed (- (var-get total-borrowed) repay-amount))
    
    (ok true))
)

;; Read-only functions
(define-read-only (get-pool-info (token principal))
    (map-get? pools token)
)

(define-read-only (get-user-deposits (user principal) (token principal))
    (map-get? user-deposits { user: user, token: token })
)

(define-read-only (get-user-borrows (user principal) (token principal))
    (map-get? user-borrows { user: user, token: token })
)

(define-read-only (get-protocol-stats)
    {
        tvl: (var-get total-value-locked),
        total-borrowed: (var-get total-borrowed),
        last-price-update: (var-get last-price-update)
    }
)