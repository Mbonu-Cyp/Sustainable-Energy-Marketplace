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
