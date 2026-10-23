package com.example.universal_can

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** UniversalCanPlugin */
class UniversalCanPlugin :
    FlutterPlugin,
    MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    private var usbManager: UsbManager? = null
    private val ACTION_USB_PERMISSION = "com.example.universal_can.USB_PERMISSION"

    private var usbConnection: UsbDeviceConnection? = null
    private var usbInterface: UsbInterface? = null
    private var usbInEndpoint: UsbEndpoint? = null
    private var usbOutEndpoint: UsbEndpoint? = null

    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    @Volatile private var isReading = false
    private var readThread: Thread? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "universal_can")
        channel.setMethodCallHandler(this)

        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "universal_can/data")
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )

        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

        val filter = IntentFilter(ACTION_USB_PERMISSION).apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }

            "openSerial" -> {

                usbManager?.deviceList?.values?.forEach { usbDevice ->
                    Log.d(
                        "USB",
                        "USB DEVICE: name=${usbDevice.deviceName}, " +
                                "vendorId=0x${usbDevice.vendorId.toString(16)}, " +
                                "productId=0x${usbDevice.productId.toString(16)}, " +
                                "class=${usbDevice.deviceClass}, " +
                                "interfaces=${usbDevice.interfaceCount}"
                    )
                }

                val device = findUsbDevice(0x0483, 0x5740)
                    ?: findUsbDevice(0x1D50, 0x606F)
                    ?: findCdcDevice()

                if (device == null) {
                    result.error("NO_DEVICE", "CANable or CDC USB device not found", null)
                    return
                }

                if (usbManager?.hasPermission(device) != true) {
                    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    } else {
                        PendingIntent.FLAG_UPDATE_CURRENT
                    }

                    val permissionIntent = PendingIntent.getBroadcast(
                        context,
                        0,
                        Intent(ACTION_USB_PERMISSION),
                        flags
                    )

                    usbManager?.requestPermission(device, permissionIntent)
                    result.success("PERMISSION_REQUESTED")
                    return
                }

                if (!openCdcDevice(device)) {
                    result.error("OPEN_FAILED", "Failed to open CDC USB device", null)
                    return
                }

                startReadThread()
                result.success("USB_DEVICE_READY")
            }

            "writeSerial" -> {
                val data = call.argument<ByteArray>("data")
                if (data == null) {
                    result.error("INVALID_DATA", "Serial data is null", null)
                    return
                }

                if (usbConnection == null || usbOutEndpoint == null) {
                    result.error("NOT_OPEN", "USB serial is not open", null)
                    return
                }

                val written = usbConnection!!.bulkTransfer(
                    usbOutEndpoint,
                    data,
                    data.size,
                    1000
                )

                if (written < 0) {
                    Log.e("USB", "USB serial write failed: $written")
                    result.error("WRITE_FAILED", "USB serial write failed", null)
                } else {
                    result.success(written)
                }
            }

            "closeSerial" -> {
                closeCdcDevice()
                result.success("CLOSED")
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        closeCdcDevice()
        try {
            context.unregisterReceiver(usbReceiver)
        } catch (e: Exception) {
            Log.e("USB", "Unregister receiver failed: ${e.message}")
        }
    }

    // ==========================================
    // USB CDC-ACM control related logic
    // ==========================================

    private fun setCp210xBaudRate(connection: UsbDeviceConnection, baudRate: Int) {
        val data = byteArrayOf(
            (baudRate and 0xFF).toByte(),
            (baudRate shr 8 and 0xFF).toByte(),
            (baudRate shr 16 and 0xFF).toByte(),
            (baudRate shr 24 and 0xFF).toByte()
        )
        // CP210x Baud Rate setting command (0x1E)
        val result = connection.controlTransfer(0x41, 0x1E, 0, 0, data, data.size, 1000)
        Log.d("USB", "CP210x BaudRate($baudRate) result = $result")
    }

    private fun findUsbDevice(vendorId: Int, productId: Int): UsbDevice? {
        return usbManager?.deviceList?.values?.firstOrNull {
            it.vendorId == vendorId && it.productId == productId
        }
    }

    private fun findCdcDevice(): UsbDevice? {
        return usbManager?.deviceList?.values?.firstOrNull { device ->
            (0 until device.interfaceCount).any { i ->
                val intf = device.getInterface(i)
                intf.interfaceClass == UsbConstants.USB_CLASS_CDC_DATA ||
                        intf.interfaceClass == UsbConstants.USB_CLASS_COMM
            }
        }
    }

    private fun openCdcDevice(device: UsbDevice): Boolean {
        val connection = usbManager?.openDevice(device) ?: return false

        var dataInterface: UsbInterface? = null
        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null

        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            var tempIn: UsbEndpoint? = null
            var tempOut: UsbEndpoint? = null

            for (j in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(j)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                    if (ep.direction == UsbConstants.USB_DIR_IN) tempIn = ep
                    if (ep.direction == UsbConstants.USB_DIR_OUT) tempOut = ep
                }
            }

            if (tempIn != null && tempOut != null) {
                dataInterface = intf
                inEp = tempIn
                outEp = tempOut
                break
            }
        }

        if (dataInterface == null || inEp == null || outEp == null) {
            connection.close()
            Log.e("USB", "Bulk Endpoints not found!")
            return false
        }

        if (!connection.claimInterface(dataInterface, true)) {
            connection.close()
            Log.e("USB", "Claim interface failed!")
            return false
        }

        this.usbConnection = connection
        this.usbInterface = dataInterface
        this.usbInEndpoint = inEp
        this.usbOutEndpoint = outEp

        // 1. CP210x Enable
        connection.controlTransfer(0x41, 0x00, 0x0001, 0, null, 0, 1000)

        // 2. DTR / RTS On
        connection.controlTransfer(0x21, 0x22, 0x03, 0, null, 0, 1000)
        connection.controlTransfer(0x41, 0x07, 0x0303, 0, null, 0, 1000)

        // 3. Set the UART speed between CP210x and STM32 MCU to 115200
        val baudData = byteArrayOf(
            0x00.toByte(), 0xC2.toByte(), 0x01.toByte(), 0x00.toByte() // 115200
        )
        connection.controlTransfer(0x41, 0x1E, 0, 0, baudData, baudData.size, 1000)

        Log.d("USB", "CP210x + SLCAN CANable successfully opened!")
        return true
    }

    private fun startReadThread() {
        if (readThread?.isAlive == true) {
            return
        }

        isReading = true

        readThread = Thread {
            val buffer = ByteArray(4096)

            while (isReading) {
                val connection = usbConnection
                val endpoint = usbInEndpoint

                if (connection == null || endpoint == null) {
                    break
                }

                // Bulk Read 수행 (타임아웃 200ms)
                val length = connection.bulkTransfer(
                    endpoint,
                    buffer,
                    buffer.size,
                    200
                )

                if (length > 0) {
                    val data = buffer.copyOf(length)

                    Handler(Looper.getMainLooper()).post {
                        eventSink?.success(data)
                    }
                }
            }
        }

        readThread?.start()
    }

    private fun closeCdcDevice() {
        isReading = false

        readThread?.interrupt()
        readThread = null

        usbConnection?.let { conn ->
            usbInterface?.let { intf ->
                conn.releaseInterface(intf)
            }
            conn.close()
        }

        usbConnection = null
        usbInterface = null
        usbInEndpoint = null
        usbOutEndpoint = null
    }

    private val usbReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {

            if (intent.action == ACTION_USB_PERMISSION) {
                val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                }

                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)

                // 권한 승인 시 바로 장치 오픈 및 수신 스레드 시작
                if (granted && device != null) {
                    if (openCdcDevice(device)) {
                        startReadThread()
                    }
                }

                channel.invokeMethod(
                    "usbPermissionResult",
                    mapOf(
                        "granted" to granted,
                        "deviceName" to (device?.deviceName ?: "")
                    )
                )
            }
        }
    }
}