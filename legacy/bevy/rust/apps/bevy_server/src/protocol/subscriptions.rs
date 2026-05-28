use super::*;

pub(super) fn mark_subscription_if_requested(
    push_state: &mut RuntimeProtocolPushState,
    message: &ClientMessage,
) {
    if matches!(message, ClientMessage::SubscribeRuntime(_)) {
        push_state.subscribed = true;
    }
}

pub(super) fn next_sequence(sequence: &mut RuntimeProtocolSequence) -> u64 {
    sequence.next = sequence.next.saturating_add(1);
    sequence.next
}
