;; Social Weave - Decentralized Social Graph Protocol
;; A Web3 social network with on-chain relationships, reputation, and monetization

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-unauthorized (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-amount (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-max-reached (err u105))
(define-constant err-blocked (err u106))
(define-constant err-not-following (err u107))
(define-constant err-self-action (err u108))
(define-constant err-cooldown (err u109))
(define-constant err-invalid-content (err u110))
(define-constant err-paused (err u111))

;; Profile & Content Limits
(define-constant max-following u1000)
(define-constant max-followers u100000)
(define-constant max-posts-per-day u50)
(define-constant max-content-length u280)
(define-constant max-bio-length u160)

;; Economic Parameters
(define-constant follow-cost u100000) ;; 0.1 STX to follow premium accounts
(define-constant post-cost u10000) ;; 0.01 STX to post
(define-constant tip-minimum u50000) ;; 0.05 STX minimum tip
(define-constant verification-cost u10000000) ;; 10 STX for verification
(define-constant platform-fee-rate u25) ;; 2.5% platform fee

;; Reputation Thresholds
(define-constant reputation-bronze u100)
(define-constant reputation-silver u500)
(define-constant reputation-gold u1000)
(define-constant reputation-platinum u5000)

;; Data Variables
(define-data-var total-users uint u0)
(define-data-var total-posts uint u0)
(define-data-var total-connections uint u0)
(define-data-var total-tips uint u0)
(define-data-var platform-revenue uint u0)
(define-data-var paused bool false)
(define-data-var post-id-counter uint u0)

;; Data Maps - Core Profile
(define-map profiles
    principal
    {
        username: (string-ascii 30),
        bio: (string-ascii 160),
        avatar-uri: (string-ascii 100),
        verified: bool,
        reputation: uint,
        followers-count: uint,
        following-count: uint,
        posts-count: uint,
        joined-block: uint,
        premium: bool,
        total-earned: uint
    }
)

;; Social Graph
(define-map connections
    { follower: principal, following: principal }
    { connected: bool, connected-at: uint }
)

(define-map blocks
    { blocker: principal, blocked: principal }
    { is-blocked: bool, blocked-at: uint }
)

;; Content
(define-map posts
    uint ;; post-id
    {
        author: principal,
        content: (string-ascii 280),
        created-at: uint,
        likes: uint,
        tips: uint,
        replies-count: uint,
        deleted: bool
    }
)

(define-map post-interactions
    { post-id: uint, user: principal }
    { liked: bool, tipped: uint, replied: bool }
)

;; Reputation & Rewards
(define-map reputation-history
    { user: principal, action-type: (string-ascii 20) }
    { points: uint, timestamp: uint }
)

(define-map daily-limits
    { user: principal, day: uint }
    { posts: uint, follows: uint, likes: uint }
)

;; Monetization
(define-map creator-subscriptions
    { creator: principal, subscriber: principal }
    { active: bool, tier: uint, expires-at: uint }
)

(define-map subscription-tiers
    { creator: principal, tier: uint }
    { price: uint, benefits: (string-ascii 100) }
)

;; Private Functions
(define-private (calculate-reputation-gain (action (string-ascii 20)))
    (if (is-eq action "post")
        u5
        (if (is-eq action "like")
            u1
            (if (is-eq action "tip")
                u10
                (if (is-eq action "follow")
                    u2
                    (if (is-eq action "verify")
                        u100
                        u0)))))
)

(define-private (get-reputation-level (reputation uint))
    (if (>= reputation reputation-platinum)
        "platinum"
        (if (>= reputation reputation-gold)
            "gold"
            (if (>= reputation reputation-silver)
                "silver"
                (if (>= reputation reputation-bronze)
                    "bronze"
                    "newbie"))))
)

(define-private (calculate-platform-fee (amount uint))
    (/ (* amount platform-fee-rate) u1000)
)

(define-private (min (a uint) (b uint))
    (if (< a b) a b)
)

;; Read-Only Functions
(define-read-only (get-profile (user principal))
    (map-get? profiles user)
)

(define-read-only (get-post (post-id uint))
    (map-get? posts post-id)
)

(define-read-only (is-following (follower principal) (following principal))
    (default-to false
        (get connected (map-get? connections { follower: follower, following: following }))
    )
)

(define-read-only (is-blocked (blocker principal) (blocked principal))
    (default-to false
        (get is-blocked (map-get? blocks { blocker: blocker, blocked: blocked }))
    )
)

(define-read-only (get-reputation-level-for-user (user principal))
    (match (map-get? profiles user)
        profile (get-reputation-level (get reputation profile))
        "none"
    )
)

(define-read-only (get-post-interaction (post-id uint) (user principal))
    (map-get? post-interactions { post-id: post-id, user: user })
)

(define-read-only (get-total-users)
    (var-get total-users)
)

(define-read-only (get-total-posts)
    (var-get total-posts)
)

(define-read-only (get-subscription-status (creator principal) (subscriber principal))
    (map-get? creator-subscriptions { creator: creator, subscriber: subscriber })
)

;; Public Functions

;; Create Profile
(define-public (create-profile (username (string-ascii 30)) (bio (string-ascii 160)) (avatar-uri (string-ascii 100)))
    (let
        (
            (user tx-sender)
            (existing-profile (map-get? profiles user))
        )
        ;; Validations
        (asserts! (is-none existing-profile) err-already-exists)
        (asserts! (not (var-get paused)) err-paused)
        (asserts! (> (len username) u0) err-invalid-content)
        
        ;; Create profile
        (map-set profiles user {
            username: username,
            bio: bio,
            avatar-uri: avatar-uri,
            verified: false,
            reputation: u10, ;; Starting reputation
            followers-count: u0,
            following-count: u0,
            posts-count: u0,
            joined-block: u1,
            premium: false,
            total-earned: u0
        })
        
        ;; Update stats
        (var-set total-users (+ (var-get total-users) u1))
        
        (ok true)
    )
)

;; Update Profile
(define-public (update-profile (bio (string-ascii 160)) (avatar-uri (string-ascii 100)))
    (let
        (
            (user tx-sender)
            (profile (unwrap! (map-get? profiles user) err-not-found))
        )
        ;; Update profile
        (map-set profiles user
            (merge profile {
                bio: bio,
                avatar-uri: avatar-uri
            })
        )
        
        (ok true)
    )
)

;; Follow User
(define-public (follow (user-to-follow principal))
    (let
        (
            (follower tx-sender)
            (follower-profile (unwrap! (map-get? profiles follower) err-not-found))
            (following-profile (unwrap! (map-get? profiles user-to-follow) err-not-found))
            (existing-connection (map-get? connections { follower: follower, following: user-to-follow }))
            (is-blocked-by (is-blocked user-to-follow follower))
        )
        ;; Validations
        (asserts! (not (var-get paused)) err-paused)
        (asserts! (not (is-eq follower user-to-follow)) err-self-action)
        (asserts! (is-none existing-connection) err-already-exists)
        (asserts! (not is-blocked-by) err-blocked)
        (asserts! (< (get following-count follower-profile) max-following) err-max-reached)
        
        ;; Handle payment for premium accounts
        (if (get premium following-profile)
            (try! (stx-transfer? follow-cost follower user-to-follow))
            true
        )
        
        ;; Create connection
        (map-set connections
            { follower: follower, following: user-to-follow }
            { connected: true, connected-at: u1 }
        )
        
        ;; Update profiles
        (map-set profiles follower
            (merge follower-profile {
                following-count: (+ (get following-count follower-profile) u1)
            })
        )
        
        (map-set profiles user-to-follow
            (merge following-profile {
                followers-count: (+ (get followers-count following-profile) u1),
                reputation: (+ (get reputation following-profile) (calculate-reputation-gain "follow"))
            })
        )
        
        ;; Update stats
        (var-set total-connections (+ (var-get total-connections) u1))
        
        (ok true)
    )
)

;; Unfollow User
(define-public (unfollow (user-to-unfollow principal))
    (let
        (
            (follower tx-sender)
            (follower-profile (unwrap! (map-get? profiles follower) err-not-found))
            (following-profile (unwrap! (map-get? profiles user-to-unfollow) err-not-found))
            (existing-connection (unwrap! (map-get? connections { follower: follower, following: user-to-unfollow }) err-not-following))
        )
        ;; Validations
        (asserts! (get connected existing-connection) err-not-following)
        
        ;; Remove connection
        (map-delete connections { follower: follower, following: user-to-unfollow })
        
        ;; Update profiles
        (map-set profiles follower
            (merge follower-profile {
                following-count: (- (get following-count follower-profile) u1)
            })
        )
        
        (map-set profiles user-to-unfollow
            (merge following-profile {
                followers-count: (- (get followers-count following-profile) u1)
            })
        )
        
        ;; Update stats
        (var-set total-connections (- (var-get total-connections) u1))
        
        (ok true)
    )
)

;; Create Post
(define-public (create-post (content (string-ascii 280)))
    (let
        (
            (author tx-sender)
            (author-profile (unwrap! (map-get? profiles author) err-not-found))
            (post-id (+ (var-get post-id-counter) u1))
        )
        ;; Validations
        (asserts! (not (var-get paused)) err-paused)
        (asserts! (> (len content) u0) err-invalid-content)
        (asserts! (>= (stx-get-balance author) post-cost) err-insufficient-funds)
        
        ;; Payment for posting
        (try! (stx-transfer? post-cost author (as-contract tx-sender)))
        
        ;; Create post
        (map-set posts post-id {
            author: author,
            content: content,
            created-at: u1,
            likes: u0,
            tips: u0,
            replies-count: u0,
            deleted: false
        })
        
        ;; Update profile
        (map-set profiles author
            (merge author-profile {
                posts-count: (+ (get posts-count author-profile) u1),
                reputation: (+ (get reputation author-profile) (calculate-reputation-gain "post"))
            })
        )
        
        ;; Update counters
        (var-set post-id-counter post-id)
        (var-set total-posts (+ (var-get total-posts) u1))
        (var-set platform-revenue (+ (var-get platform-revenue) post-cost))
        
        (ok post-id)
    )
)

;; Like Post
(define-public (like-post (post-id uint))
    (let
        (
            (user tx-sender)
            (post (unwrap! (map-get? posts post-id) err-not-found))
            (author (get author post))
            (author-profile (unwrap! (map-get? profiles author) err-not-found))
            (interaction (map-get? post-interactions { post-id: post-id, user: user }))
        )
        ;; Validations
        (asserts! (not (var-get paused)) err-paused)
        (asserts! (not (get deleted post)) err-not-found)
        (asserts! (or (is-none interaction) (not (get liked (unwrap! interaction err-not-found)))) err-already-exists)
        
        ;; Update post
        (map-set posts post-id
            (merge post {
                likes: (+ (get likes post) u1)
            })
        )
        
        ;; Update interaction
        (map-set post-interactions
            { post-id: post-id, user: user }
            {
                liked: true,
                tipped: (match interaction inter (get tipped inter) u0),
                replied: (match interaction inter (get replied inter) false)
            }
        )
        
        ;; Update author reputation
        (map-set profiles author
            (merge author-profile {
                reputation: (+ (get reputation author-profile) (calculate-reputation-gain "like"))
            })
        )
        
        (ok true)
    )
)

;; Tip Post
(define-public (tip-post (post-id uint) (amount uint))
    (let
        (
            (tipper tx-sender)
            (post (unwrap! (map-get? posts post-id) err-not-found))
            (author (get author post))
            (author-profile (unwrap! (map-get? profiles author) err-not-found))
            (platform-fee (calculate-platform-fee amount))
            (author-amount (- amount platform-fee))
            (interaction (map-get? post-interactions { post-id: post-id, user: tipper }))
        )
        ;; Validations
        (asserts! (not (var-get paused)) err-paused)
        (asserts! (not (get deleted post)) err-not-found)
        (asserts! (>= amount tip-minimum) err-invalid-amount)
        (asserts! (not (is-eq tipper author)) err-self-action)
        (asserts! (>= (stx-get-balance tipper) amount) err-insufficient-funds)
        
        ;; Transfer tip
        (try! (stx-transfer? author-amount tipper author))
        (try! (stx-transfer? platform-fee tipper (as-contract tx-sender)))
        
        ;; Update post
        (map-set posts post-id
            (merge post {
                tips: (+ (get tips post) amount)
            })
        )
        
        ;; Update interaction
        (map-set post-interactions
            { post-id: post-id, user: tipper }
            {
                liked: (match interaction inter (get liked inter) false),
                tipped: (+ (match interaction inter (get tipped inter) u0) amount),
                replied: (match interaction inter (get replied inter) false)
            }
        )
        
        ;; Update profiles
        (map-set profiles author
            (merge author-profile {
                reputation: (+ (get reputation author-profile) (calculate-reputation-gain "tip")),
                total-earned: (+ (get total-earned author-profile) author-amount)
            })
        )
        
        ;; Update stats
        (var-set total-tips (+ (var-get total-tips) amount))
        (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
        
        (ok amount)
    )
)

;; Delete Post
(define-public (delete-post (post-id uint))
    (let
        (
            (user tx-sender)
            (post (unwrap! (map-get? posts post-id) err-not-found))
        )
        ;; Validations
        (asserts! (is-eq user (get author post)) err-unauthorized)
        (asserts! (not (get deleted post)) err-not-found)
        
        ;; Mark as deleted
        (map-set posts post-id
            (merge post {
                deleted: true
            })
        )
        
        (ok true)
    )
)

;; Block User
(define-public (block-user (user-to-block principal))
    (let
        (
            (blocker tx-sender)
        )
        ;; Validations
        (asserts! (not (is-eq blocker user-to-block)) err-self-action)
        
        ;; Create block
        (map-set blocks
            { blocker: blocker, blocked: user-to-block }
            { is-blocked: true, blocked-at: u1 }
        )
        
        ;; Remove any existing connection
        (map-delete connections { follower: blocker, following: user-to-block })
        (map-delete connections { follower: user-to-block, following: blocker })
        
        (ok true)
    )
)

;; Unblock User
(define-public (unblock-user (user-to-unblock principal))
    (let
        (
            (blocker tx-sender)
            (block-record (unwrap! (map-get? blocks { blocker: blocker, blocked: user-to-unblock }) err-not-found))
        )
        ;; Remove block
        (map-delete blocks { blocker: blocker, blocked: user-to-unblock })
        
        (ok true)
    )
)

;; Get Verified
(define-public (get-verified)
    (let
        (
            (user tx-sender)
            (profile (unwrap! (map-get? profiles user) err-not-found))
        )
        ;; Validations
        (asserts! (not (get verified profile)) err-already-exists)
        (asserts! (>= (stx-get-balance user) verification-cost) err-insufficient-funds)
        (asserts! (>= (get reputation profile) reputation-silver) err-not-found)
        
        ;; Payment
        (try! (stx-transfer? verification-cost user (as-contract tx-sender)))
        
        ;; Update profile
        (map-set profiles user
            (merge profile {
                verified: true,
                reputation: (+ (get reputation profile) (calculate-reputation-gain "verify"))
            })
        )
        
        ;; Update revenue
        (var-set platform-revenue (+ (var-get platform-revenue) verification-cost))
        
        (ok true)
    )
)

;; Enable Premium Account
(define-public (enable-premium)
    (let
        (
            (user tx-sender)
            (profile (unwrap! (map-get? profiles user) err-not-found))
        )
        ;; Validations
        (asserts! (not (get premium profile)) err-already-exists)
        (asserts! (get verified profile) err-not-found)
        
        ;; Update profile
        (map-set profiles user
            (merge profile {
                premium: true
            })
        )
        
        (ok true)
    )
)

;; Create Subscription Tier
(define-public (create-subscription-tier (tier uint) (price uint) (benefits (string-ascii 100)))
    (let
        (
            (creator tx-sender)
            (profile (unwrap! (map-get? profiles creator) err-not-found))
        )
        ;; Validations
        (asserts! (get premium profile) err-unauthorized)
        (asserts! (<= tier u5) err-max-reached)
        (asserts! (> price u0) err-invalid-amount)
        
        ;; Create tier
        (map-set subscription-tiers
            { creator: creator, tier: tier }
            { price: price, benefits: benefits }
        )
        
        (ok true)
    )
)

;; Subscribe to Creator
(define-public (subscribe (creator principal) (tier uint) (duration uint))
    (let
        (
            (subscriber tx-sender)
            (tier-info (unwrap! (map-get? subscription-tiers { creator: creator, tier: tier }) err-not-found))
            (price (get price tier-info))
            (total-cost (* price duration))
            (platform-fee (calculate-platform-fee total-cost))
            (creator-amount (- total-cost platform-fee))
        )
        ;; Validations
        (asserts! (not (is-eq subscriber creator)) err-self-action)
        (asserts! (>= (stx-get-balance subscriber) total-cost) err-insufficient-funds)
        
        ;; Payment
        (try! (stx-transfer? creator-amount subscriber creator))
        (try! (stx-transfer? platform-fee subscriber (as-contract tx-sender)))
        
        ;; Create/Update subscription
        (map-set creator-subscriptions
            { creator: creator, subscriber: subscriber }
            { active: true, tier: tier, expires-at: (+ u1 (* duration u4320)) }
        )
        
        ;; Update stats
        (var-set platform-revenue (+ (var-get platform-revenue) platform-fee))
        
        (ok true)
    )
)

;; Admin Functions

;; Pause Contract
(define-public (pause-contract (pause-state bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (var-set paused pause-state)
        (ok pause-state)
    )
)

;; Withdraw Platform Revenue
(define-public (withdraw-revenue (amount uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (<= amount (var-get platform-revenue)) err-insufficient-funds)
        
        (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
        (var-set platform-revenue (- (var-get platform-revenue) amount))
        
        (ok amount)
    )
)