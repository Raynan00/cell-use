// Phone Probe: PNG capture and authenticated input share one owned session.
// The capture future is retained while input is serviced, never restarted by a tap.
async fn run_png_input_probe(
    readiness: &DeveloperReady,
    adapter: &mut tcp::handle::AdapterHandle,
    handshake: &mut RsdHandshake,
    emitter: &EventEmitter,
    mut controls: ControlGate,
    mut cancellation: tokio::sync::watch::Receiver<bool>,
) -> Result<(), PublicFailure> {
    for name in [UNIVERSAL_HID_SERVICE, INDIGO_HID_SERVICE, ORIENTATION_SERVICE] {
        require_prepared_service(handshake, name)?;
    }
    emitter.phase(DhConnectionPhase::OpeningInput, DhSessionState::Connected)?;
    let mut universal_hid = stage(INPUT_TIMEOUT, input_service_connection_failed(),
        UniversalHidServiceClient::connect_rsd(adapter, handshake)).await?;
    let mut indigo_hid = stage(INPUT_TIMEOUT, input_service_connection_failed(),
        IndigoHidClient::connect_rsd(adapter, handshake)).await?;
    let mut orientation = stage(INPUT_TIMEOUT, orientation_service_connection_failed(),
        OrientationServiceClient::connect_rsd(adapter, handshake)).await?;
    let initial_orientation = stage(INPUT_TIMEOUT, orientation_state_failed(),
        orientation.current_orientation()).await?;
    let keyboard_service_id = stage(INPUT_TIMEOUT, input_service_connection_failed(),
        universal_hid.create_keyboard_service(&KeyboardServiceConfiguration::default())).await?;
    tokio::time::sleep(Duration::from_millis(300)).await;
    controls.enable_input();
    emitter.input_ready()?;
    let mut cleanup = InputCleanupState::default();
    let deadline = tokio::time::sleep(Duration::from_secs(120));
    tokio::pin!(deadline);
    let result = 'probe: loop {
        let capture = async {
            let dimensions = capture_screenshot(readiness, adapter, handshake, emitter).await?;
            let mut geometry = DhDisplayGeometry {
                pixel_width: dimensions.width, pixel_height: dimensions.height,
                orientation: DhOrientation::Unknown as u32,
                non_flat_orientation: DhOrientation::Unknown as u32,
                orientation_locked: 0, reserved: [0; 7],
            };
            // This portrait-only experiment rejects rotated frames in the app.
            update_geometry_orientation(&mut geometry, &initial_orientation)?;
            emitter.display_geometry(geometry)?;
            emitter.phase(DhConnectionPhase::Ready, DhSessionState::Connected)?;
            tokio::time::sleep(Duration::from_secs(1)).await;
            Ok::<(), PublicFailure>(())
        };
        tokio::pin!(capture);
        loop {
            tokio::select! {
                biased;
                _ = cancellation.changed() => break 'probe Ok(()),
                _ = &mut deadline => break 'probe Ok(()),
                command = controls.receive() => {
                    let Some(command) = command else {
                        break 'probe Err(PublicFailure::new("control_channel_closed",
                            "png_input", false, "The input channel closed."));
                    };
                    // The PNG runtime admits touch, keyboard and cleanup only.
                    if !png_input_command_allowed(&command) {
                        break 'probe Err(PublicFailure::new("unsupported_probe_command",
                            "png_input", false, "This runtime accepts touch, keyboard and cleanup."));
                    }
                    if let Err(failure) = handle_control_command(command, None, 0,
                        &mut universal_hid, keyboard_service_id, &mut indigo_hid,
                        &mut orientation, &mut cleanup).await {
                        break 'probe Err(failure);
                    }
                }
                outcome = &mut capture => {
                    if let Err(failure) = outcome { break 'probe Err(failure); }
                    break;
                }
            }
        }
    };
    cleanup_inputs(&mut cleanup, &mut universal_hid, keyboard_service_id, &mut indigo_hid).await;
    result
}

fn png_input_command_allowed(command: &ControlCommand) -> bool {
    matches!(command, ControlCommand::Touch(_) | ControlCommand::Keyboard(_) |
                     ControlCommand::ReleaseAllInput)
}

#[cfg(test)]
mod png_input_tests {
    use super::*;
    #[test]
    fn admits_gestures_keyboard_cleanup_but_not_video() {
        for intent in [TouchIntent::Down { x: 1, y: 2 }, TouchIntent::Move { x: 2, y: 3 },
                       TouchIntent::Up { x: 2, y: 3 }, TouchIntent::Cancel, TouchIntent::Tap { x: 1, y: 2 }] {
            assert!(png_input_command_allowed(&ControlCommand::Touch(intent)));
        }
        assert!(png_input_command_allowed(&ControlCommand::Keyboard(KeyboardIntent::Tap { usage: 4, modifiers: 0 })));
        assert!(png_input_command_allowed(&ControlCommand::ReleaseAllInput));
        assert!(!png_input_command_allowed(&ControlCommand::VideoNegotiation));
        assert!(!png_input_command_allowed(&ControlCommand::Rotate(RotationIntent::Left)));
        assert!(!png_input_command_allowed(&ControlCommand::VideoControlDatagram(crate::model::VideoControlDatagram { bytes: vec![] })));
    }
}
