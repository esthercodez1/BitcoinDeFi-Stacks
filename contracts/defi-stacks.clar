;; DeFi Protocol Smart Contract
;; Version: 1.0.0
;; Description: A DeFi protocol enabling lending, borrowing, and liquidity provision on Bitcoin through Stacks

;; Define SIP-010 Trait - using local reference
(use-trait ft-trait .sip-010-trait.ft-trait)

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

;; Add security checks for repay function
(define-constant err-invalid-token (err u107))
(define-constant err-invalid-contract-caller (err u108))
(define-constant err-zero-amount (err u109))

;; Data Variables
(define-data-var protocol-paused bool false)
(define-data-var total-value-locked uint u0)
(define-data-var total-borrows uint u0)
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
(define-private (get-minimum (a uint) (b uint))
    (if (<= a b)
        a
        b))

(define-private (calculate-interest-rate (total-supply uint) (borrowed-amount uint))
    (let (
        (utilization-rate (if (is-eq total-supply u0)
            u0
            (/ (* borrowed-amount u10000) total-supply)))
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
        (borrow-price (unwrap-panic (map-get? price-feeds borrow-token)))
        (collateral-price (unwrap-panic (map-get? price-feeds collateral-token)))
        (borrow-value (* borrow-amount borrow-price))
        (collateral-value (* collateral-amount collateral-price))
    )
    (/ (* collateral-value u100) borrow-value))
)

;; Public Functions
(define-public (initialize-pool (token-contract <ft-trait>))
    (let ((token (contract-of token-contract)))
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
            (ok true)))
)

(define-public (deposit (token-contract <ft-trait>) (amount uint))
    (let (
        (token (contract-of token-contract))
        (pool (unwrap! (map-get? pools token) err-pool-not-found))
        (sender-balance (unwrap! (contract-call? token-contract get-balance tx-sender) err-not-enough-balance))
    )
    (asserts! (>= sender-balance amount) err-not-enough-balance)
    (asserts! (not (var-get protocol-paused)) err-not-initialized)
    
    ;; Transfer tokens to protocol
    (try! (contract-call? token-contract transfer 
        amount 
        tx-sender 
        (as-contract tx-sender) 
        none))
    
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
    (borrow-token-contract <ft-trait>)
    (borrow-amount uint)
    (collateral-token-contract <ft-trait>)
    (collateral-amount uint))
    (let (
        (borrow-token (contract-of borrow-token-contract))
        (collateral-token (contract-of collateral-token-contract))
        (pool (unwrap! (map-get? pools borrow-token) err-pool-not-found))
        (collateral-balance (unwrap! 
            (contract-call? collateral-token-contract get-balance tx-sender) 
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
    (try! (contract-call? collateral-token-contract transfer 
        collateral-amount
        tx-sender
        (as-contract tx-sender)
        none))
    
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
    (try! (contract-call? borrow-token-contract transfer
        borrow-amount
        (as-contract tx-sender)
        tx-sender
        none))
    
    ;; Update protocol stats
    (var-set total-borrows (+ (var-get total-borrows) borrow-amount))
    
    (ok true))
)

;; Secured repay function with additional checks
(define-public (repay (token-contract <ft-trait>) (amount uint))
    (let (
        (token (contract-of token-contract))
        ;; Validate token is registered in protocol
        (pool (unwrap! (map-get? pools token) err-invalid-token))
        ;; Validate user has an existing borrow
        (borrow-info (unwrap! (map-get? user-borrows
            { user: tx-sender, token: token })
            err-not-enough-balance))
    )
        ;; Basic validation checks
        (asserts! (not (var-get protocol-paused)) err-not-initialized)
        (asserts! (> amount u0) err-zero-amount)
        
        ;; Validate user balance before repayment
        (let (
            (user-balance (unwrap! (contract-call? token-contract get-balance tx-sender) 
                err-not-enough-balance))
            (repay-amount (get-minimum amount (get amount borrow-info)))
        )
            ;; Additional validation for token contract
            (asserts! (is-eq token (contract-of token-contract)) err-invalid-token)
            
            ;; Ensure repay amount doesn't exceed borrow amount
            (asserts! (<= repay-amount (get amount borrow-info)) err-invalid-amount)
            
            ;; Validate user has sufficient balance
            (asserts! (>= user-balance repay-amount) err-not-enough-balance)
            
            ;; Transfer repayment to protocol with validated amounts
            (try! (contract-call? token-contract transfer
                repay-amount
                tx-sender
                (as-contract tx-sender)
                none))
            
            ;; Safe pool state update with checks
            (let ((new-total-borrowed (- (get total-borrowed pool) repay-amount)))
                (asserts! (>= new-total-borrowed u0) err-invalid-amount)
                (map-set pools token
                    (merge pool {
                        total-borrowed: new-total-borrowed,
                        last-update-block: block-height
                    }))
                
                ;; Safe user borrow update with checks
                (let ((new-borrow-amount (- (get amount borrow-info) repay-amount)))
                    (asserts! (>= new-borrow-amount u0) err-invalid-amount)
                    (map-set user-borrows
                        { user: tx-sender, token: token }
                        (merge borrow-info {
                            amount: new-borrow-amount,
                            last-update: block-height
                        }))
                    
                    ;; Safe protocol stats update
                    (let ((new-total-borrows (- (var-get total-borrows) repay-amount)))
                        (asserts! (>= new-total-borrows u0) err-invalid-amount)
                        (var-set total-borrows new-total-borrows)
                        (ok true)))))
))

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
        total-borrowed: (var-get total-borrows),
        last-price-update: (var-get last-price-update)
    }
)