#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os

def run_cmd(cmd):
    """Run shell command and return output"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def get_device_info(pci_addr):
    """Get detailed device information"""
    ret, out, err = run_cmd(f"lspci -s {pci_addr}")
    if ret == 0 and out.strip():
        # Parse: 00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)
        parts = out.strip().split(': ', 2)
        if len(parts) >= 2:
            return parts[1].strip()
    return "Unknown device"

def get_ena_devices():
    """Get list of ENA network devices"""
    ret, out, err = run_cmd("lspci -d 1d0f:")
    devices = []
    for line in out.strip().split('\n'):
        if line and 'Ethernet' in line:
            pci_addr = line.split()[0]
            full_addr = f"0000:{pci_addr}"
            desc = get_device_info(pci_addr)
            devices.append({'addr': full_addr, 'desc': desc, 'short_addr': pci_addr})
    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Get current driver
    driver = "none"
    driver_link = f"/sys/bus/pci/devices/{pci_addr}/driver"
    if os.path.exists(driver_link):
        try:
            driver = os.path.basename(os.readlink(driver_link))
        except OSError:
            pass
    
    # Get interface name if available
    interface = ""
    net_dir = f"/sys/bus/pci/devices/{pci_addr}/net/"
    if os.path.exists(net_dir):
        try:
            files = os.listdir(net_dir)
            if files:
                interface = sorted(files)[0]
        except OSError:
            pass
    
    # Check if interface is active
    active = False
    if interface:
        try:
            with open(f"/sys/class/net/{interface}/operstate", "r") as f:
                state = f.read().strip()
                active = (state == "up")
        except OSError:
            pass
    
    return driver, interface, active

def bind_device(pci_addr, driver):
    """Bind PCI device to specified driver using driver_override method"""
    print(f"Binding {pci_addr} to {driver}")
    
    # Get current driver
    current_driver, _, _ = get_driver_info(pci_addr)
    
    if current_driver == driver:
        print(f"Device {pci_addr} already bound to {driver}")
        return True
    
    # Step 1: Unbind from current driver if bound
    if current_driver != "none":
        print(f"  Unbinding from {current_driver}")
        try:
            with open(f"/sys/bus/pci/devices/{pci_addr}/driver/unbind", "w") as f:
                f.write(pci_addr)
        except OSError as e:
            print(f"  Warning: Failed to unbind from {current_driver}: {e}")
    
    # Step 2: Set driver override
    print(f"  Setting driver override to {driver}")
    try:
        with open(f"/sys/bus/pci/devices/{pci_addr}/driver_override", "w") as f:
            f.write(f"{driver}\n")
    except OSError as e:
        print(f"  Error: Failed to set driver override: {e}")
        return False
    
    # Step 3: For vfio-pci, ensure module is loaded and device ID is added
    if driver == "vfio-pci":
        print("  Loading vfio-pci module")
        run_cmd("modprobe vfio-pci")
        
        print("  Adding ENA device ID to vfio-pci")
        try:
            with open("/sys/bus/pci/drivers/vfio-pci/new_id", "w") as f:
                f.write("1d0f ec20")
        except OSError as e:
            print(f"  Warning: Failed to add device ID: {e}")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        count = 0
        try:
            count = len(os.listdir("/sys/kernel/iommu_groups/"))
        except OSError:
            pass

        if count <= 2:  # Only . and .. directories equivalent
            print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
            try:
                with open("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "w") as f:
                    f.write("1")
            except OSError:
                pass
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    try:
        with open("/sys/bus/pci/drivers_probe", "w") as f:
            f.write(pci_addr)
    except OSError as e:
        print(f"  Error: Failed to probe device: {e}")
        return False
    
    # Verify binding worked
    new_driver, _, _ = get_driver_info(pci_addr)
    if new_driver == driver:
        print(f"  Successfully bound {pci_addr} to {driver}")
        return True
    else:
        print(f"  Error: Device bound to {new_driver} instead of {driver}")
        return False

def show_status():
    """Show device binding status"""
    devices = get_ena_devices()
    
    # Group devices by driver type
    dpdk_devices = []
    kernel_devices = []
    
    for dev in devices:
        driver, interface, active = get_driver_info(dev['addr'])
        dev['driver'] = driver
        dev['interface'] = interface
        dev['active'] = active
        
        if driver == "vfio-pci":
            dpdk_devices.append(dev)
        else:
            kernel_devices.append(dev)
    
    # Display DPDK devices
    if dpdk_devices:
        print("Network devices using DPDK-compatible driver")
        print("============================================")
        for dev in dpdk_devices:
            unused_drivers = "ena" if dev['driver'] == "vfio-pci" else "vfio-pci"
            print(f"{dev['addr']} 'Elastic Network Adapter (ENA) ec20' drv={dev['driver']} unused={unused_drivers}")
    
    # Display kernel devices
    if kernel_devices:
        print("\nNetwork devices using kernel driver")
        print("===================================")
        for dev in kernel_devices:
            unused_drivers = "vfio-pci"
            active_str = " *Active*" if dev['active'] else ""
            if dev['interface']:
                print(f"{dev['addr']} 'Elastic Network Adapter (ENA) ec20' if={dev['interface']} drv={dev['driver']} unused={unused_drivers}{active_str}")
            else:
                print(f"{dev['addr']} '{dev['driver']}'")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        show_status()
    elif sys.argv[1] == "--status" or sys.argv[1] == "-s":
        show_status()
    elif sys.argv[1] == "--bind" or sys.argv[1] == "-b":
        if len(sys.argv) != 4:
            print("Usage: dpdk-devbind.py --bind <driver> <pci_addr>")
            print("   or: dpdk-devbind.py -b <driver> <pci_addr>")
            sys.exit(1)
        success = bind_device(sys.argv[3], sys.argv[2])
        if not success:
            sys.exit(1)
    elif sys.argv[1] == "--help" or sys.argv[1] == "-h":
        print("Usage:")
        print("  dpdk-devbind.py                    - Show device status")
        print("  dpdk-devbind.py -s|--status        - Show device status")
        print("  dpdk-devbind.py -b|--bind <driver> <pci_addr> - Bind device")
        print("  dpdk-devbind.py -h|--help          - Show this help")
    else:
        show_status()