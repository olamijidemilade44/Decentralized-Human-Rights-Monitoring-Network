;; Freedom of Expression Monitoring Contract
;; Tracks censorship and restrictions on free speech worldwide

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-INCIDENT-NOT-FOUND (err u302))
(define-constant ERR-ALREADY-EXISTS (err u303))

;; Data Variables
(define-data-var next-incident-id uint u1)
(define-data-var total-incidents uint u0)
(define-data-var total-journalists-affected uint u0)

;; Data Maps
(define-map censorship-incidents
  { incident-id: uint }
  {
    reporter: principal,
    incident-type: (string-ascii 50),
    target-type: (string-ascii 30),
    country: (string-ascii 50),
    date-occurred: uint,
    severity-score: uint,
    description: (string-ascii 500),
    evidence-hash: (string-ascii 64),
    government-involved: bool,
    verified: bool,
    resolution-status: (string-ascii 20)
  }
)

(define-map journalist-safety
  { journalist-id: (string-ascii 64) }
  {
    name-hash: (string-ascii 64),
    country: (string-ascii 50),
    media-outlet: (string-ascii 100),
    threat-level: uint,
    incidents-count: uint,
    last-incident-date: uint,
    protection-status: (string-ascii 20),
    contact-hash: (string-ascii 64)
  }
)

(define-map media-restrictions
  { country: (string-ascii 50), restriction-type: (string-ascii 50) }
  {
    restriction-level: uint,
    date-implemented: uint,
    affected-outlets: uint,
    description: (string-ascii 300),
    enforcement-agency: (string-ascii 100),
    legal-basis: (string-ascii 200)
  }
)

(define-map press-freedom-index
  { country: (string-ascii 50) }
  {
    freedom-score: uint,
    ranking: uint,
    incidents-count: uint,
    journalists-imprisoned: uint,
    media-outlets-closed: uint,
    last-updated: uint
  }
)

(define-map transparency-violations
  { violation-id: uint }
  {
    government-entity: (string-ascii 100),
    country: (string-ascii 50),
    violation-type: (string-ascii 50),
    information-denied: (string-ascii 200),
    date-reported: uint,
    legal-challenge: bool,
    resolution: (string-ascii 100)
  }
)

;; Authorization Maps
(define-map authorized-monitors principal bool)
(define-map media-organizations principal bool)

;; Public Functions

;; Report a censorship incident
(define-public (report-censorship-incident
  (incident-type (string-ascii 50))
  (target-type (string-ascii 30))
  (country (string-ascii 50))
  (severity-score uint)
  (description (string-ascii 500))
  (evidence-hash (string-ascii 64))
  (government-involved bool))
  (let
    (
      (incident-id (var-get next-incident-id))
    )
    ;; Validate inputs
    (asserts! (> (len incident-type) u0) ERR-INVALID-INPUT)
    (asserts! (> (len country) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= severity-score u1) (<= severity-score u10)) ERR-INVALID-INPUT)
    (asserts! (> (len evidence-hash) u0) ERR-INVALID-INPUT)

    ;; Record incident
    (map-set censorship-incidents
      { incident-id: incident-id }
      {
        reporter: tx-sender,
        incident-type: incident-type,
        target-type: target-type,
        country: country,
        date-occurred: block-height,
        severity-score: severity-score,
        description: description,
        evidence-hash: evidence-hash,
        government-involved: government-involved,
        verified: false,
        resolution-status: "OPEN"
      }
    )

    ;; Update counters
    (var-set next-incident-id (+ incident-id u1))
    (var-set total-incidents (+ (var-get total-incidents) u1))

    ;; Update country press freedom index
    (let
      (
        (current-index (default-to { freedom-score: u50, ranking: u0, incidents-count: u0, journalists-imprisoned: u0, media-outlets-closed: u0, last-updated: u0 }
                                   (map-get? press-freedom-index { country: country })))
      )
      (map-set press-freedom-index
        { country: country }
        (merge current-index {
          incidents-count: (+ (get incidents-count current-index) u1),
          last-updated: block-height
        })
      )
    )

    (ok incident-id)
  )
)

;; Register journalist for safety monitoring
(define-public (register-journalist
  (journalist-id (string-ascii 64))
  (name-hash (string-ascii 64))
  (country (string-ascii 50))
  (media-outlet (string-ascii 100))
  (contact-hash (string-ascii 64)))
  (begin
    ;; Validate inputs
    (asserts! (> (len journalist-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len name-hash) u0) ERR-INVALID-INPUT)
    (asserts! (> (len country) u0) ERR-INVALID-INPUT)

    ;; Check if journalist already exists
    (asserts! (is-none (map-get? journalist-safety { journalist-id: journalist-id })) ERR-ALREADY-EXISTS)

    ;; Register journalist
    (map-set journalist-safety
      { journalist-id: journalist-id }
      {
        name-hash: name-hash,
        country: country,
        media-outlet: media-outlet,
        threat-level: u1,
        incidents-count: u0,
        last-incident-date: u0,
        protection-status: "ACTIVE",
        contact-hash: contact-hash
      }
    )

    (var-set total-journalists-affected (+ (var-get total-journalists-affected) u1))
    (ok true)
  )
)

;; Report media restriction
(define-public (report-media-restriction
  (country (string-ascii 50))
  (restriction-type (string-ascii 50))
  (restriction-level uint)
  (affected-outlets uint)
  (description (string-ascii 300))
  (enforcement-agency (string-ascii 100))
  (legal-basis (string-ascii 200)))
  (begin
    ;; Check authorization
    (asserts! (default-to false (map-get? authorized-monitors tx-sender)) ERR-NOT-AUTHORIZED)

    ;; Validate inputs
    (asserts! (> (len country) u0) ERR-INVALID-INPUT)
    (asserts! (and (>= restriction-level u1) (<= restriction-level u5)) ERR-INVALID-INPUT)

    ;; Record restriction
    (map-set media-restrictions
      { country: country, restriction-type: restriction-type }
      {
        restriction-level: restriction-level,
        date-implemented: block-height,
        affected-outlets: affected-outlets,
        description: description,
        enforcement-agency: enforcement-agency,
        legal-basis: legal-basis
      }
    )

    (ok true)
  )
)

;; Update journalist threat level
(define-public (update-journalist-threat
  (journalist-id (string-ascii 64))
  (new-threat-level uint)
  (incident-description (string-ascii 200)))
  (let
    (
      (journalist (unwrap! (map-get? journalist-safety { journalist-id: journalist-id }) ERR-INCIDENT-NOT-FOUND))
    )
    ;; Check authorization
    (asserts! (default-to false (map-get? authorized-monitors tx-sender)) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-threat-level u1) (<= new-threat-level u5)) ERR-INVALID-INPUT)

    ;; Update threat level
    (map-set journalist-safety
      { journalist-id: journalist-id }
      (merge journalist {
        threat-level: new-threat-level,
        incidents-count: (+ (get incidents-count journalist) u1),
        last-incident-date: block-height
      })
    )

    (ok true)
  )
)

;; Report transparency violation
(define-public (report-transparency-violation
  (government-entity (string-ascii 100))
  (country (string-ascii 50))
  (violation-type (string-ascii 50))
  (information-denied (string-ascii 200)))
  (let
    (
      (violation-id (var-get next-incident-id))
    )
    ;; Validate inputs
    (asserts! (> (len government-entity) u0) ERR-INVALID-INPUT)
    (asserts! (> (len country) u0) ERR-INVALID-INPUT)
    (asserts! (> (len violation-type) u0) ERR-INVALID-INPUT)

    ;; Record violation
    (map-set transparency-violations
      { violation-id: violation-id }
      {
        government-entity: government-entity,
        country: country,
        violation-type: violation-type,
        information-denied: information-denied,
        date-reported: block-height,
        legal-challenge: false,
        resolution: "PENDING"
      }
    )

    (var-set next-incident-id (+ violation-id u1))
    (ok violation-id)
  )
)

;; Verify incident (authorized monitors only)
(define-public (verify-incident (incident-id uint))
  (let
    (
      (incident (unwrap! (map-get? censorship-incidents { incident-id: incident-id }) ERR-INCIDENT-NOT-FOUND))
    )
    ;; Check authorization
    (asserts! (default-to false (map-get? authorized-monitors tx-sender)) ERR-NOT-AUTHORIZED)

    ;; Update verification status
    (map-set censorship-incidents
      { incident-id: incident-id }
      (merge incident { verified: true })
    )

    (ok true)
  )
)

;; Authorize monitor (contract owner only)
(define-public (authorize-monitor (monitor principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-monitors monitor true)
    (ok true)
  )
)

;; Read-only Functions

;; Get censorship incident
(define-read-only (get-censorship-incident (incident-id uint))
  (map-get? censorship-incidents { incident-id: incident-id })
)

;; Get journalist safety information
(define-read-only (get-journalist-safety (journalist-id (string-ascii 64)))
  (map-get? journalist-safety { journalist-id: journalist-id })
)

;; Get media restrictions
(define-read-only (get-media-restrictions (country (string-ascii 50)) (restriction-type (string-ascii 50)))
  (map-get? media-restrictions { country: country, restriction-type: restriction-type })
)

;; Get press freedom index
(define-read-only (get-press-freedom-index (country (string-ascii 50)))
  (map-get? press-freedom-index { country: country })
)

;; Get transparency violation
(define-read-only (get-transparency-violation (violation-id uint))
  (map-get? transparency-violations { violation-id: violation-id })
)

;; Get total statistics
(define-read-only (get-expression-statistics)
  {
    total-incidents: (var-get total-incidents),
    total-journalists: (var-get total-journalists-affected),
    next-incident-id: (var-get next-incident-id)
  }
)
