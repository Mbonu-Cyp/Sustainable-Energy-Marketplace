;; Sustainable Energy Marketplace
;; Description: Smart contract for trading renewable energy credits and certificates

;; Constants and Error Codes
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INVALID-AMOUNT (err u2))
(define-constant ERR-INSUFFICIENT-BALANCE (err u3))
(define-constant ERR-ASSET-NOT-FOUND (err u4))
(define-constant ERR-LISTING-NOT-FOUND (err u5))
(define-constant ERR-INVALID-PRICE (err u6))
(define-constant ERR-ALREADY-VERIFIED (err u7))
(define-constant ERR-NOT-VERIFIED (err u8))
(define-constant ERR-EXPIRED (err u9))
(define-constant ERR-ALREADY-EXISTS (err u10))

;; Data Maps
(define-map EnergyAssets
    { asset-id: uint }
    {
        producer: principal,
        energy-type: (string-utf8 20),
        amount: uint,            ;; in kWh
        generation-date: uint,   ;; block height
        expiry-date: uint,      ;; block height
        location: (string-utf8 100),
        verified: bool,
        certification: (optional (string-utf8 50)),
        remaining-amount: uint   ;; in kWh
    }
)

(define-map MarketListings
    { listing-id: uint }
    {
        asset-id: uint,
        seller: principal,
        price-per-kwh: uint,    ;; in microSTX
        min-purchase: uint,      ;; in kWh
        available-amount: uint,  ;; in kWh
        creation-date: uint,     ;; block height
        active: bool,
        total-sold: uint        ;; in kWh
    }
)

(define-map ProducerProfiles
    { producer: principal }
    {
        name: (string-utf8 100),
        verification-status: bool,
        total-generated: uint,   ;; in kWh
        total-sold: uint,        ;; in kWh
        rating: uint,            ;; out of 100
        registration-date: uint  ;; block height
    }
)

(define-map ConsumerBalances
    { consumer: principal }
    {
        total-purchased: uint,   ;; in kWh
        active-credits: uint,    ;; in kWh
        spent-credits: uint,     ;; in kWh
        last-purchase: uint      ;; block height
    }
)

(define-map Verifiers
    { address: principal }
    {
        name: (string-utf8 100),
        credentials: (string-utf8 200),
        verifications-count: uint,
        active-since: uint       ;; block height
    }
)

;; Data Variables
(define-data-var contract-owner principal tx-sender)
(define-data-var next-asset-id uint u1)
(define-data-var next-listing-id uint u1)
(define-data-var platform-fee-rate uint u25)     ;; 0.25%
(define-data-var min-purchase-amount uint u100)  ;; 100 kWh
(define-data-var credit-validity-period uint u52560) ;; ~365 days in blocks


;; Read-Only Functions
(define-read-only (get-energy-asset (asset-id uint))
    (map-get? EnergyAssets { asset-id: asset-id })
)

(define-read-only (get-market-listing (listing-id uint))
    (map-get? MarketListings { listing-id: listing-id })
)

(define-read-only (get-producer-profile (producer principal))
    (map-get? ProducerProfiles { producer: producer })
)

(define-read-only (get-consumer-balance (consumer principal))
    (map-get? ConsumerBalances { consumer: consumer })
)

(define-read-only (calculate-platform-fee (amount uint))
    (/ (* amount (var-get platform-fee-rate)) u10000)
)

(define-public (register-energy-asset 
    (energy-type (string-utf8 20))
    (amount uint)
    (location (string-utf8 100))
    (expiry-blocks uint)
)
    (let
        ((asset-id (var-get next-asset-id))
         (caller tx-sender)
         (producer-profile (get-producer-profile caller)))
        
        ;; Validate producer and amount
        (asserts! (is-some producer-profile) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Unwrap producer profile and proceed with registration
        (let ((prev-profile (unwrap! producer-profile ERR-NOT-AUTHORIZED)))
            ;; Create energy asset
            (map-set EnergyAssets
                { asset-id: asset-id }
                {
                    producer: caller,
                    energy-type: energy-type,
                    amount: amount,
                    generation-date: block-height,
                    expiry-date: (+ block-height expiry-blocks),
                    location: location,
                    verified: false,
                    certification: none,
                    remaining-amount: amount
                }
            )
            
            ;; Update producer profile
            (map-set ProducerProfiles
                { producer: caller }
                (merge prev-profile {
                    total-generated: (+ (get total-generated prev-profile) amount)
                })
            )
            
            ;; Increment asset counter and return
            (var-set next-asset-id (+ asset-id u1))
            (ok asset-id)
        )
    )
)
