# Universal CAN Example

This Android example demonstrates `BluetoothCanClient` with a Bluetooth Classic serial device whose firmware implements the package's 16-byte binary CAN protocol and CRC-8.

Enter the paired device's Bluetooth address, connect and start CAN, then send the sample standard CAN frame or watch received frames in the log. The sample frame uses CAN ID `0x123` with an 8-byte payload.

This example does not demonstrate USB SLCAN. See the package README for the transport and device compatibility details.
