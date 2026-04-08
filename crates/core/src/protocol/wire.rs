#![allow(dead_code)]

use serde::Serialize;
use serde::de::DeserializeOwned;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use super::error::{ProtocolError, Result};
use super::message::{
    MessageEnvelope, MessageKind, PROTOCOL_VERSION, ReceiverMessage, SenderMessage, TransferRole,
};

pub(crate) const MAX_MESSAGE_BYTES: usize = 16 * 1024 * 1024;

async fn read_frame<R, T>(reader: &mut R) -> Result<T>
where
    R: AsyncRead + Unpin,
    T: DeserializeOwned,
{
    let message_len = reader
        .read_u32()
        .await
        .map_err(|source| ProtocolError::frame_read("reading message length", source))?
        as usize;
    if message_len > MAX_MESSAGE_BYTES {
        return Err(ProtocolError::message_too_large(
            message_len,
            MAX_MESSAGE_BYTES,
        ));
    }

    let mut message_buf = vec![0_u8; message_len];
    reader
        .read_exact(&mut message_buf)
        .await
        .map_err(|source| ProtocolError::frame_read("reading message bytes", source))?;
    serde_json::from_slice(&message_buf)
        .map_err(|source| ProtocolError::message_deserialize("parsing message body", source))
}

async fn write_frame<W, T>(writer: &mut W, value: &T) -> Result<()>
where
    W: AsyncWrite + Unpin,
    T: Serialize,
{
    let bytes = serde_json::to_vec(value)
        .map_err(|source| ProtocolError::message_serialize("serializing message body", source))?;
    if bytes.len() > MAX_MESSAGE_BYTES {
        return Err(ProtocolError::message_too_large(
            bytes.len(),
            MAX_MESSAGE_BYTES,
        ));
    }

    writer
        .write_u32(bytes.len() as u32)
        .await
        .map_err(|source| ProtocolError::frame_write("writing message length", source))?;
    writer
        .write_all(&bytes)
        .await
        .map_err(|source| ProtocolError::frame_write("writing message bytes", source))?;
    writer
        .flush()
        .await
        .map_err(|source| ProtocolError::frame_write("flushing message", source))?;
    Ok(())
}

fn validate_envelope(envelope: &MessageEnvelope, expected_role: TransferRole) -> Result<()> {
    if envelope.version != PROTOCOL_VERSION {
        return Err(ProtocolError::unsupported_version(
            PROTOCOL_VERSION,
            envelope.version,
        ));
    }

    if envelope.role != expected_role {
        return Err(ProtocolError::unexpected_role(expected_role, envelope.role));
    }

    Ok(())
}

fn validate_sender_kind(message: &SenderMessage, kind: MessageKind) -> Result<()> {
    if message.kind() != kind {
        return Err(ProtocolError::unexpected_message_kind(
            "sender",
            kind,
            message.kind(),
        ));
    }
    Ok(())
}

fn validate_receiver_kind(message: &ReceiverMessage, kind: MessageKind) -> Result<()> {
    if message.kind() != kind {
        return Err(ProtocolError::unexpected_message_kind(
            "receiver",
            kind,
            message.kind(),
        ));
    }
    Ok(())
}

fn sender_envelope(message: &SenderMessage) -> Result<MessageEnvelope> {
    Ok(MessageEnvelope {
        version: PROTOCOL_VERSION,
        role: message.role(),
        kind: message.kind(),
        message: serde_json::to_value(message).map_err(|source| {
            ProtocolError::message_serialize("serializing sender message", source)
        })?,
    })
}

fn receiver_envelope(message: &ReceiverMessage) -> Result<MessageEnvelope> {
    Ok(MessageEnvelope {
        version: PROTOCOL_VERSION,
        role: message.role(),
        kind: message.kind(),
        message: serde_json::to_value(message).map_err(|source| {
            ProtocolError::message_serialize("serializing receiver message", source)
        })?,
    })
}

fn sender_message_from_envelope(envelope: MessageEnvelope) -> Result<SenderMessage> {
    validate_envelope(&envelope, TransferRole::Sender)?;
    let message: SenderMessage = serde_json::from_value(envelope.message)
        .map_err(|source| ProtocolError::message_deserialize("parsing sender message", source))?;
    validate_sender_kind(&message, envelope.kind)?;
    Ok(message)
}

fn receiver_message_from_envelope(envelope: MessageEnvelope) -> Result<ReceiverMessage> {
    validate_envelope(&envelope, TransferRole::Receiver)?;
    let message: ReceiverMessage = serde_json::from_value(envelope.message)
        .map_err(|source| ProtocolError::message_deserialize("parsing receiver message", source))?;
    validate_receiver_kind(&message, envelope.kind)?;
    Ok(message)
}

pub(crate) async fn read_sender_message<R>(reader: &mut R) -> Result<SenderMessage>
where
    R: AsyncRead + Unpin,
{
    sender_message_from_envelope(read_frame(reader).await?)
}

pub(crate) async fn write_sender_message<W>(writer: &mut W, message: &SenderMessage) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    write_frame(writer, &sender_envelope(message)?).await
}

pub(crate) async fn read_receiver_message<R>(reader: &mut R) -> Result<ReceiverMessage>
where
    R: AsyncRead + Unpin,
{
    receiver_message_from_envelope(read_frame(reader).await?)
}

pub(crate) async fn write_receiver_message<W>(
    writer: &mut W,
    message: &ReceiverMessage,
) -> Result<()>
where
    W: AsyncWrite + Unpin,
{
    write_frame(writer, &receiver_envelope(message)?).await
}

#[cfg(test)]
mod tests {
    use super::{
        read_receiver_message, read_sender_message, write_frame, write_receiver_message,
        write_sender_message,
    };
    use crate::protocol::message::{
        ManifestItem, MessageEnvelope, MessageKind, Offer, PROTOCOL_VERSION, ReceiverMessage,
        SenderMessage, TransferErrorCode, TransferManifest, TransferResult, TransferRole,
        TransferStatus,
    };
    use tokio::io::duplex;

    #[tokio::test]
    async fn sender_message_roundtrips_through_envelope()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let (mut a, mut b) = duplex(1024);
        let message = SenderMessage::Offer(Offer {
            session_id: "session-1".to_owned(),
            manifest: TransferManifest {
                items: vec![ManifestItem::File {
                    path: "a.txt".to_owned(),
                    size: 1,
                }],
            },
        });

        write_sender_message(&mut a, &message).await?;
        let decoded = read_sender_message(&mut b).await?;

        assert_eq!(message, decoded);
        Ok(())
    }

    #[tokio::test]
    async fn receiver_message_roundtrips_through_envelope()
    -> std::result::Result<(), Box<dyn std::error::Error>> {
        let (mut a, mut b) = duplex(1024);
        let message = ReceiverMessage::TransferResult(TransferResult {
            session_id: "session-1".to_owned(),
            status: TransferStatus::Error {
                code: TransferErrorCode::Cancelled,
                message: "stopped".to_owned(),
            },
        });

        write_receiver_message(&mut a, &message).await?;
        let decoded = read_receiver_message(&mut b).await?;

        assert_eq!(message, decoded);
        Ok(())
    }

    #[test]
    fn envelope_carries_version_role_and_kind() {
        let envelope = MessageEnvelope {
            version: PROTOCOL_VERSION,
            role: TransferRole::Sender,
            kind: MessageKind::Hello,
            message: serde_json::json!({
                "type": "hello",
                "version": PROTOCOL_VERSION,
                "session_id": "session-1",
                "identity": {
                    "role": "sender",
                    "device_name": "sam-mac",
                    "device_type": "laptop",
                }
            }),
        };

        let json = serde_json::to_string(&envelope).unwrap();

        assert!(json.contains("\"version\":2"));
        assert!(json.contains("\"role\":\"sender\""));
        assert!(json.contains("\"kind\":\"hello\""));
    }

    #[tokio::test]
    async fn rejects_wrong_role_on_read() {
        let (mut a, mut b) = duplex(1024);
        let envelope = MessageEnvelope {
            version: PROTOCOL_VERSION,
            role: TransferRole::Receiver,
            kind: MessageKind::Hello,
            message: serde_json::json!({
                "type": "hello",
                "version": PROTOCOL_VERSION,
                "session_id": "session-1",
                "identity": {
                    "role": "receiver",
                    "device_name": "phone",
                    "device_type": "phone",
                }
            }),
        };

        write_frame(&mut a, &envelope).await.unwrap();
        let err = read_sender_message(&mut b)
            .await
            .expect_err("expected role mismatch");
        assert!(format!("{err:#}").contains("unexpected message role"));
    }

    #[tokio::test]
    async fn rejects_wrong_version_on_read() {
        let (mut a, mut b) = duplex(1024);
        let envelope = MessageEnvelope {
            version: PROTOCOL_VERSION - 1,
            role: TransferRole::Sender,
            kind: MessageKind::Offer,
            message: serde_json::json!({
                "type": "offer",
                "session_id": "session-1",
                "manifest": {
                    "items": []
                }
            }),
        };

        write_frame(&mut a, &envelope).await.unwrap();
        let err = read_sender_message(&mut b)
            .await
            .expect_err("expected version mismatch");
        assert!(format!("{err:#}").contains("unsupported protocol version"));
    }
}
