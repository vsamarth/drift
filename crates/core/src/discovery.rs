use anyhow::{Result, bail};
use time::OffsetDateTime;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DiscoveryState {
    Open,
    Claimed,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiscoveryError {
    Claimed,
    Expired,
}

#[derive(Debug, Clone)]
pub struct DiscoverySession {
    ticket: Option<String>,
    state: DiscoveryState,
    expires_at: OffsetDateTime,
}

impl DiscoverySession {
    pub fn new(
        ticket: String,
        created_at: OffsetDateTime,
        expires_at: OffsetDateTime,
    ) -> Result<Self> {
        if ticket.trim().is_empty() {
            bail!("ticket must not be empty");
        }

        if expires_at <= created_at {
            bail!("expiry must be after creation time");
        }

        Ok(Self {
            ticket: Some(ticket),
            state: DiscoveryState::Open,
            expires_at,
        })
    }

    pub fn state(&mut self, now: OffsetDateTime) -> DiscoveryState {
        self.refresh(now);
        self.state
    }

    pub fn claim(&mut self, now: OffsetDateTime) -> Result<String, DiscoveryError> {
        self.refresh(now);

        match self.state {
            DiscoveryState::Open => {
                self.state = DiscoveryState::Claimed;
                self.ticket.take().ok_or(DiscoveryError::Claimed)
            }
            DiscoveryState::Claimed => Err(DiscoveryError::Claimed),
            DiscoveryState::Expired => Err(DiscoveryError::Expired),
        }
    }

    pub fn is_removable(&mut self, now: OffsetDateTime) -> bool {
        self.state(now) == DiscoveryState::Expired
    }

    fn refresh(&mut self, now: OffsetDateTime) {
        if self.state == DiscoveryState::Open && now >= self.expires_at {
            self.state = DiscoveryState::Expired;
            self.ticket = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use time::Duration;

    fn sample_times() -> (OffsetDateTime, OffsetDateTime) {
        let created_at = OffsetDateTime::now_utc();
        let expires_at = created_at + Duration::minutes(5);
        (created_at, expires_at)
    }

    #[test]
    fn new_session_starts_open() {
        let (created_at, expires_at) = sample_times();
        let mut session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");

        assert_eq!(session.state(created_at), DiscoveryState::Open);
    }

    #[test]
    fn claim_transitions_open_session_to_claimed_once() {
        let (created_at, expires_at) = sample_times();
        let mut session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");

        let claimed = session.claim(created_at).expect("claim");
        assert_eq!(claimed, "ticket");
        assert_eq!(session.state(created_at), DiscoveryState::Claimed);
        assert_eq!(session.claim(created_at), Err(DiscoveryError::Claimed));
    }

    #[test]
    fn expiry_transitions_open_session_to_expired() {
        let (created_at, expires_at) = sample_times();
        let mut session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");

        let after_expiry = expires_at + Duration::seconds(1);
        assert_eq!(session.state(after_expiry), DiscoveryState::Expired);
        assert_eq!(session.claim(after_expiry), Err(DiscoveryError::Expired));
    }

    #[test]
    fn removable_only_after_expiry() {
        let (created_at, expires_at) = sample_times();
        let mut open_session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");
        assert!(!open_session.is_removable(created_at));

        let mut claimed_session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");
        claimed_session.claim(created_at).expect("claim");
        assert!(!claimed_session.is_removable(created_at));

        let mut expired_session =
            DiscoverySession::new("ticket".to_owned(), created_at, expires_at).expect("session");
        assert!(expired_session.is_removable(expires_at + Duration::seconds(1)));
    }

    #[test]
    fn invalid_construction_is_rejected() {
        let created_at = OffsetDateTime::now_utc();
        let expires_at = created_at;

        assert!(
            DiscoverySession::new("".to_owned(), created_at, created_at + Duration::seconds(1))
                .is_err()
        );
        assert!(DiscoverySession::new("ticket".to_owned(), created_at, expires_at).is_err());
    }
}
