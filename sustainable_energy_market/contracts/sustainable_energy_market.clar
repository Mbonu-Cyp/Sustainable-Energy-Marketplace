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

;; Market Functions
(define-public (create-market-listing
    (asset-id uint)
    (price-per-kwh uint)
    (min-purchase uint)
)
    (let
        ((listing-id (var-get next-listing-id))
         (caller tx-sender)
         (asset (unwrap! (get-energy-asset asset-id) ERR-ASSET-NOT-FOUND)))
        
        ;; Validate listing
        (asserts! (is-eq caller (get producer asset)) ERR-NOT-AUTHORIZED)
        (asserts! (get verified asset) ERR-NOT-VERIFIED)
        (asserts! (> (get remaining-amount asset) u0) ERR-INSUFFICIENT-BALANCE)
        (asserts! (>= min-purchase (var-get min-purchase-amount)) ERR-INVALID-AMOUNT)
        
        (ok (begin
            ;; Create listing
            (map-set MarketListings
                { listing-id: listing-id }
                {
                    asset-id: asset-id,
                    seller: caller,
                    price-per-kwh: price-per-kwh,
                    min-purchase: min-purchase,
                    available-amount: (get remaining-amount asset),
                    creation-date: block-height,
                    active: true,
                    total-sold: u0
                }
            )
            
            ;; Increment listing counter
            (var-set next-listing-id (+ listing-id u1))
            listing-id
        ))
    )
)


(define-public (purchase-energy-credits
   (listing-id uint)
   (amount uint)
)
   (let
       ((caller tx-sender)
        (listing (unwrap! (get-market-listing listing-id) ERR-LISTING-NOT-FOUND))
        (asset (unwrap! (get-energy-asset (get asset-id listing)) ERR-ASSET-NOT-FOUND))
        (total-cost (* amount (get price-per-kwh listing)))
        (platform-fee (calculate-platform-fee total-cost)))
       
       ;; Validate purchase
       (asserts! (get active listing) ERR-LISTING-NOT-FOUND)
       (asserts! (>= amount (get min-purchase listing)) ERR-INVALID-AMOUNT)
       (asserts! (<= amount (get available-amount listing)) ERR-INSUFFICIENT-BALANCE)
       (asserts! (< block-height (get expiry-date asset)) ERR-EXPIRED)
       
       ;; Process payment
       (try! (stx-transfer? total-cost caller (get seller listing)))
       (try! (stx-transfer? platform-fee caller (var-get contract-owner)))
       
       (let ((consumer-balance (get-consumer-balance caller))
             (producer-profile (get-producer-profile (get seller listing))))
           
           ;; Update listing
           (map-set MarketListings
               { listing-id: listing-id }
               (merge listing {
                   available-amount: (- (get available-amount listing) amount),
                   total-sold: (+ (get total-sold listing) amount),
                   active: (> (- (get available-amount listing) amount) u0)
               })
           )
           
           ;; Update asset
           (map-set EnergyAssets
               { asset-id: (get asset-id listing) }
               (merge asset {
                   remaining-amount: (- (get remaining-amount asset) amount)
               })
           )
           
           ;; Update consumer balance
           (match consumer-balance
               prev-balance (map-set ConsumerBalances
                   { consumer: caller }
                   {
                       total-purchased: (+ (get total-purchased prev-balance) amount),
                       active-credits: (+ (get active-credits prev-balance) amount),
                       spent-credits: (get spent-credits prev-balance),
                       last-purchase: block-height
                   }
               )
               (map-set ConsumerBalances
                   { consumer: caller }
                   {
                       total-purchased: amount,
                       active-credits: amount,
                       spent-credits: u0,
                       last-purchase: block-height
                   }
               )
           )
           
           ;; Update producer profile if exists
           (match producer-profile
               prev-profile (begin
                   (map-set ProducerProfiles
                       { producer: (get seller listing) }
                       (merge prev-profile {
                           total-sold: (+ (get total-sold prev-profile) amount)
                       })
                   )
                   (ok true)
               )
               (ok true) ;; If no profile exists, still succeed
           )
       )
   )
)
