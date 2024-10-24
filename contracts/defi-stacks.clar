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