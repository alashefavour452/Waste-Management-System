;; Disposal Fee Calculation Contract
;; Determines costs based on waste type and disposal method

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-INPUT (err u401))
(define-constant ERR-WASTE-TYPE-NOT-FOUND (err u402))
(define-constant ERR-PAYMENT-NOT-FOUND (err u403))
(define-constant ERR-INSUFFICIENT-PAYMENT (err u404))

;; Data Variables
(define-data-var total-fees-collected uint u0)
(define-data-var base-fee-rate uint u10) ;; Base fee per kg in microSTX
(define-data-var payment-counter uint u0)

;; Data Maps
(define-map waste-type-rates
  { waste-type: (string-ascii 30) }
  {
    base-rate: uint,
    disposal-multiplier: uint,
    recycling-discount: uint,
    hazard-surcharge: uint
  })

(define-map disposal-methods
  { method: (string-ascii 30) }
  {
    cost-multiplier: uint,
    environmental-impact: uint,
    processing-fee: uint
  })

(define-map fee-calculations
  { calculation-id: uint }
  {
    waste-type: (string-ascii 30),
    amount: uint,
    disposal-method: (string-ascii 30),
    base-fee: uint,
    total-fee: uint,
    timestamp: uint,
    paid: bool
  })

(define-map payment-records
  { payment-id: uint }
  {
    calculation-id: uint,
    payer: principal,
    amount-paid: uint,
    payment-timestamp: uint,
    payment-method: (string-ascii 20)
  })

;; Initialize waste type rates
(map-set waste-type-rates { waste-type: "organic" }
  { base-rate: u5, disposal-multiplier: u100, recycling-discount: u20, hazard-surcharge: u0 })
(map-set waste-type-rates { waste-type: "plastic" }
  { base-rate: u15, disposal-multiplier: u120, recycling-discount: u30, hazard-surcharge: u0 })
(map-set waste-type-rates { waste-type: "paper" }
  { base-rate: u8, disposal-multiplier: u90, recycling-discount: u40, hazard-surcharge: u0 })
(map-set waste-type-rates { waste-type: "glass" }
  { base-rate: u12, disposal-multiplier: u110, recycling-discount: u35, hazard-surcharge: u0 })
(map-set waste-type-rates { waste-type: "metal" }
  { base-rate: u20, disposal-multiplier: u130, recycling-discount: u50, hazard-surcharge: u0 })
(map-set waste-type-rates { waste-type: "electronic" }
  { base-rate: u50, disposal-multiplier: u200, recycling-discount: u25, hazard-surcharge: u100 })
(map-set waste-type-rates { waste-type: "hazardous" }
  { base-rate: u100, disposal-multiplier: u300, recycling-discount: u0, hazard-surcharge: u500 })
(map-set waste-type-rates { waste-type: "general" }
  { base-rate: u10, disposal-multiplier: u100, recycling-discount: u10, hazard-surcharge: u0 })

;; Initialize disposal methods
(map-set disposal-methods { method: "landfill" }
  { cost-multiplier: u100, environmental-impact: u80, processing-fee: u5 })
(map-set disposal-methods { method: "incineration" }
  { cost-multiplier: u150, environmental-impact: u60, processing-fee: u20 })
(map-set disposal-methods { method: "recycling" }
  { cost-multiplier: u80, environmental-impact: u20, processing-fee: u15 })
(map-set disposal-methods { method: "composting" }
  { cost-multiplier: u70, environmental-impact: u10, processing-fee: u10 })
(map-set disposal-methods { method: "hazardous-treatment" }
  { cost-multiplier: u400, environmental-impact: u30, processing-fee: u100 })

;; Private Functions
(define-private (get-waste-rate (waste-type (string-ascii 30)))
  (default-to
    { base-rate: u10, disposal-multiplier: u100, recycling-discount: u0, hazard-surcharge: u0 }
    (map-get? waste-type-rates { waste-type: waste-type })))

(define-private (get-disposal-method-data (method (string-ascii 30)))
  (default-to
    { cost-multiplier: u100, environmental-impact: u50, processing-fee: u10 }
    (map-get? disposal-methods { method: method })))

;; Public Functions

;; Calculate disposal fee
(define-public (calculate-fee
  (waste-type (string-ascii 30))
  (amount uint)
  (disposal-method (string-ascii 30)))
  (let (
    (waste-rates (get-waste-rate waste-type))
    (method-data (get-disposal-method-data disposal-method))
    (calculation-id (+ (var-get payment-counter) u1))
    (base-fee (* amount (get base-rate waste-rates)))
    (method-fee (* base-fee (get cost-multiplier method-data)))
    (disposal-fee (/ (* method-fee (get disposal-multiplier waste-rates)) u10000))
    (processing-fee (* amount (get processing-fee method-data)))
    (hazard-fee (* amount (get hazard-surcharge waste-rates)))
    (discount (if (is-eq disposal-method "recycling")
                (/ (* disposal-fee (get recycling-discount waste-rates)) u100)
                u0))
    (total-fee (+ (+ (+ disposal-fee processing-fee) hazard-fee) (- u0 discount)))
  )
    (asserts! (> amount u0) ERR-INVALID-INPUT)
    (asserts! (> (len waste-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len disposal-method) u0) ERR-INVALID-INPUT)

    (map-set fee-calculations
      { calculation-id: calculation-id }
      {
        waste-type: waste-type,
        amount: amount,
        disposal-method: disposal-method,
        base-fee: base-fee,
        total-fee: total-fee,
        timestamp: block-height,
        paid: false
      })

    (var-set payment-counter calculation-id)

    (ok { calculation-id: calculation-id, total-fee: total-fee })))

;; Process payment for calculated fee
(define-public (process-payment
  (calculation-id uint)
  (payment-method (string-ascii 20)))
  (let (
    (calculation-data (unwrap! (map-get? fee-calculations { calculation-id: calculation-id }) ERR-INVALID-INPUT))
    (total-fee (get total-fee calculation-data))
    (payment-id (+ calculation-id u1000)) ;; Simple payment ID generation
  )
    (asserts! (not (get paid calculation-data)) ERR-INVALID-INPUT)
    (asserts! (> total-fee u0) ERR-INVALID-INPUT)

    ;; Mark calculation as paid
    (map-set fee-calculations
      { calculation-id: calculation-id }
      {
        waste-type: (get waste-type calculation-data),
        amount: (get amount calculation-data),
        disposal-method: (get disposal-method calculation-data),
        base-fee: (get base-fee calculation-data),
        total-fee: total-fee,
        timestamp: (get timestamp calculation-data),
        paid: true
      })

    ;; Record payment
    (map-set payment-records
      { payment-id: payment-id }
      {
        calculation-id: calculation-id,
        payer: tx-sender,
        amount-paid: total-fee,
        payment-timestamp: block-height,
        payment-method: payment-method
      })

    ;; Update total fees collected
    (var-set total-fees-collected (+ (var-get total-fees-collected) total-fee))

    (ok payment-id)))

;; Update waste type rates (admin only)
(define-public (update-waste-type-rate
  (waste-type (string-ascii 30))
  (base-rate uint)
  (disposal-multiplier uint)
  (recycling-discount uint)
  (hazard-surcharge uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len waste-type) u0) ERR-INVALID-INPUT)
    (asserts! (<= recycling-discount u100) ERR-INVALID-INPUT)

    (map-set waste-type-rates
      { waste-type: waste-type }
      {
        base-rate: base-rate,
        disposal-multiplier: disposal-multiplier,
        recycling-discount: recycling-discount,
        hazard-surcharge: hazard-surcharge
      })

    (ok true)))

;; Update disposal method rates (admin only)
(define-public (update-disposal-method
  (method (string-ascii 30))
  (cost-multiplier uint)
  (environmental-impact uint)
  (processing-fee uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> (len method) u0) ERR-INVALID-INPUT)
    (asserts! (<= environmental-impact u100) ERR-INVALID-INPUT)

    (map-set disposal-methods
      { method: method }
      {
        cost-multiplier: cost-multiplier,
        environmental-impact: environmental-impact,
        processing-fee: processing-fee
      })

    (ok true)))

;; Update base fee rate (admin only)
(define-public (update-base-fee-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-rate u0) ERR-INVALID-INPUT)

    (var-set base-fee-rate new-rate)
    (ok true)))

;; Read-only Functions

;; Get fee calculation details
(define-read-only (get-fee-calculation (calculation-id uint))
  (map-get? fee-calculations { calculation-id: calculation-id }))

;; Get payment record
(define-read-only (get-payment-record (payment-id uint))
  (map-get? payment-records { payment-id: payment-id }))

;; Get waste type rates
(define-read-only (get-waste-type-rates (waste-type (string-ascii 30)))
  (map-get? waste-type-rates { waste-type: waste-type }))

;; Get disposal method info
(define-read-only (get-disposal-method-info (method (string-ascii 30)))
  (map-get? disposal-methods { method: method }))

;; Get total fees collected
(define-read-only (get-total-fees-collected)
  (var-get total-fees-collected))

;; Get base fee rate
(define-read-only (get-base-fee-rate)
  (var-get base-fee-rate))

;; Calculate fee preview (without storing)
(define-read-only (preview-fee-calculation
  (waste-type (string-ascii 30))
  (amount uint)
  (disposal-method (string-ascii 30)))
  (let (
    (waste-rates (get-waste-rate waste-type))
    (method-data (get-disposal-method-data disposal-method))
    (base-fee (* amount (get base-rate waste-rates)))
    (method-fee (* base-fee (get cost-multiplier method-data)))
    (disposal-fee (/ (* method-fee (get disposal-multiplier waste-rates)) u10000))
    (processing-fee (* amount (get processing-fee method-data)))
    (hazard-fee (* amount (get hazard-surcharge waste-rates)))
    (discount (if (is-eq disposal-method "recycling")
                (/ (* disposal-fee (get recycling-discount waste-rates)) u100)
                u0))
    (total-fee (+ (+ (+ disposal-fee processing-fee) hazard-fee) (- u0 discount)))
  )
    {
      base-fee: base-fee,
      disposal-fee: disposal-fee,
      processing-fee: processing-fee,
      hazard-fee: hazard-fee,
      discount: discount,
      total-fee: total-fee
    }))
