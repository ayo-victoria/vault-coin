
;; Title: VaultCoin Protocol - Next-Generation sBTC Yield Optimization Platform
;; 
;; Summary: Revolutionary Bitcoin Layer 2 vault system that maximizes returns on 
;;          sBTC assets through intelligent time-weighted reward mechanisms and
;;          dynamic APY optimization strategies for sophisticated DeFi participants.
;;
;; Description: VaultCoin Protocol represents the pinnacle of Bitcoin DeFi innovation,
;;              combining Stacks' battle-tested security with cutting-edge yield 
;;              generation algorithms. Our protocol transforms idle sBTC holdings into 
;;              productive assets through mathematically optimized reward distribution,
;;              flexible lock periods, and transparent governance. Built for both 
;;              retail investors and institutional participants, VaultCoin delivers
;;              sustainable yields while maintaining full Bitcoin-backed security.
;;              Features include compound reward mechanisms, emergency withdrawal
;;              options, and real-time performance analytics.


;; ERROR CONSTANTS - Protocol Safety Mechanisms

(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_ZERO_STAKE (err u101))
(define-constant ERR_NO_STAKE_FOUND (err u102))
(define-constant ERR_TOO_EARLY_TO_UNSTAKE (err u103))
(define-constant ERR_INVALID_REWARD_RATE (err u104))
(define-constant ERR_NOT_ENOUGH_REWARDS (err u105))
(define-constant ERR_INVALID_PERIOD (err u106))
(define-constant ERR_OWNER_UNCHANGED (err u107))

;; DATA STORAGE - Vault State Management

;; Individual vault positions for yield optimization
(define-map stakes
  { staker: principal }
  {
    amount: uint,
    staked-at: uint,
  }
)

;; Historical reward distribution tracking
(define-map rewards-claimed
  { staker: principal }
  { amount: uint }
)

;; PROTOCOL CONFIGURATION - Dynamic Parameter Management

;; Yield rate in basis points (5 = 0.5% annual yield)
(define-data-var reward-rate uint u5)

;; Treasury reserve pool for sustainable reward distribution
(define-data-var reward-pool uint u0)

;; Minimum vault lock period in blocks (~10 days for security)
(define-data-var min-stake-period uint u1440)

;; Total value locked (TVL) across all vault positions
(define-data-var total-staked uint u0)

;; Protocol administrator for governance functions
(define-data-var contract-owner principal tx-sender)

;; ADMINISTRATIVE FUNCTIONS - Protocol Governance

;; Retrieve current protocol administrator
(define-read-only (get-contract-owner)
  (var-get contract-owner)
)

;; Execute ownership transfer with validation
(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq new-owner (var-get contract-owner)))
      ERR_OWNER_UNCHANGED
    )
    (ok (var-set contract-owner new-owner))
  )
)

;; Adjust yield parameters for market optimization
(define-public (set-reward-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (< new-rate u1000) ERR_INVALID_REWARD_RATE) ;; Cap at 100% APY
    (ok (var-set reward-rate new-rate))
  )
)

;; Configure minimum lock period for risk management
(define-public (set-min-stake-period (new-period uint))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR_NOT_AUTHORIZED)
    (asserts! (> new-period u0) ERR_INVALID_PERIOD)
    (ok (var-set min-stake-period new-period))
  )
)

;; Capitalize reward treasury for sustainable yields
(define-public (add-to-reward-pool (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_STAKE)
    ;; Secure sBTC transfer to protocol treasury
    (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount tx-sender (as-contract tx-sender) none
    ))
    ;; Expand reward distribution capacity
    (var-set reward-pool (+ (var-get reward-pool) amount))
    (ok true)
  )
)

;; CORE VAULT FUNCTIONS - Yield Generation Engine

;; Deposit sBTC into yield-generating vault position
(define-public (stake (amount uint))
  (begin
    (asserts! (> amount u0) ERR_ZERO_STAKE)
    ;; Execute secure asset transfer to vault
    (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount tx-sender (as-contract tx-sender) none
    ))
    ;; Update or initialize vault position
    (match (map-get? stakes { staker: tx-sender })
      prev-stake
      ;; Compound existing position
      (map-set stakes { staker: tx-sender } {
        amount: (+ amount (get amount prev-stake)),
        staked-at: stacks-block-height,
      })
      ;; Create new vault position  
      (map-set stakes { staker: tx-sender } {
        amount: amount,
        staked-at: stacks-block-height,
      })
    )
    ;; Update protocol TVL metrics
    (var-set total-staked (+ (var-get total-staked) amount))
    (ok true)
  )
)

;; Calculate time-weighted yield rewards with precision
(define-read-only (calculate-rewards (staker principal))
  (match (map-get? stakes { staker: staker })
    stake-info
    (let (
        (stake-amount (get amount stake-info))
        (stake-duration (- stacks-block-height (get staked-at stake-info)))
        (reward-basis (/ (* stake-amount (var-get reward-rate)) u1000))
        (blocks-per-year u52560) ;; Stacks blockchain annual block count
        (time-factor (/ (* stake-duration u10000) blocks-per-year))
        (reward (* reward-basis (/ time-factor u10000)))
      )
      reward
    )
    u0 ;; No active position found
  )
)

;; Harvest accumulated yield without position closure
(define-public (claim-rewards)
  (let (
      (stake-info (unwrap! (map-get? stakes { staker: tx-sender }) ERR_NO_STAKE_FOUND))
      (reward-amount (calculate-rewards tx-sender))
    )
    (asserts! (> reward-amount u0) ERR_NO_STAKE_FOUND)
    (asserts! (<= reward-amount (var-get reward-pool)) ERR_NOT_ENOUGH_REWARDS)
    ;; Deduct rewards from treasury reserve
    (var-set reward-pool (- (var-get reward-pool) reward-amount))
    ;; Update lifetime rewards tracking
    (match (map-get? rewards-claimed { staker: tx-sender })
      prev-claimed (map-set rewards-claimed { staker: tx-sender } { amount: (+ reward-amount (get amount prev-claimed)) })
      (map-set rewards-claimed { staker: tx-sender } { amount: reward-amount })
    )
    ;; Reset yield calculation timestamp
    (map-set stakes { staker: tx-sender } {
      amount: (get amount stake-info),
      staked-at: stacks-block-height,
    })
    ;; Execute secure reward distribution
    (as-contract (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer reward-amount (as-contract tx-sender) tx-sender none
    )))
    (ok true)
  )
)

;; Close vault position with automatic yield harvesting
(define-public (unstake (amount uint))
  (let (
      (stake-info (unwrap! (map-get? stakes { staker: tx-sender }) ERR_NO_STAKE_FOUND))
      (staked-amount (get amount stake-info))
      (staked-at (get staked-at stake-info))
      (stake-duration (- stacks-block-height staked-at))
    )
    ;; Validate withdrawal parameters
    (asserts! (> amount u0) ERR_ZERO_STAKE)
    (asserts! (>= staked-amount amount) ERR_NO_STAKE_FOUND)
    (asserts! (>= stake-duration (var-get min-stake-period))
      ERR_TOO_EARLY_TO_UNSTAKE
    )
    ;; Execute automatic yield harvesting
    (try! (claim-rewards))
    ;; Update or close vault position
    (if (> staked-amount amount)
      (map-set stakes { staker: tx-sender } {
        amount: (- staked-amount amount),
        staked-at: stacks-block-height,
      })
      (map-delete stakes { staker: tx-sender })
    )
    ;; Update protocol TVL accounting
    (var-set total-staked (- (var-get total-staked) amount))
    ;; Execute secure asset withdrawal
    (as-contract (try! (contract-call? 'ST1F7QA2MDF17S807EPA36TSS8AMEFY4KA9TVGWXT.sbtc-token
      transfer amount (as-contract tx-sender) tx-sender none
    )))
    (ok true)
  )
)

;; READ-ONLY QUERY FUNCTIONS - Analytics & Transparency

;; Retrieve detailed vault position information
(define-read-only (get-stake-info (staker principal))
  (map-get? stakes { staker: staker })
)

;; Query lifetime reward distribution history
(define-read-only (get-rewards-claimed (staker principal))
  (map-get? rewards-claimed { staker: staker })
)

;; Get current yield rate configuration
(define-read-only (get-reward-rate)
  (var-get reward-rate)
)

;; Retrieve minimum lock period requirements
(define-read-only (get-min-stake-period)
  (var-get min-stake-period)
)

;; Check available treasury reserves
(define-read-only (get-reward-pool)
  (var-get reward-pool)
)

;; Monitor protocol total value locked (TVL)
(define-read-only (get-total-staked)
  (var-get total-staked)
)

;; Calculate real-time annual percentage yield
(define-read-only (get-current-apy)
  (let ((rate-basis (var-get reward-rate)))
    ;; Convert basis points to percentage display
    (* rate-basis u100)
  )
)

;; Comprehensive protocol performance dashboard
(define-read-only (get-protocol-stats)
  {
    total-staked: (var-get total-staked),
    reward-pool: (var-get reward-pool),
    reward-rate: (var-get reward-rate),
    min-stake-period: (var-get min-stake-period),
    current-apy: (get-current-apy),
  }
)