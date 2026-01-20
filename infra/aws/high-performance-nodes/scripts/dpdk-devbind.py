#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os
import re

# Validation patterns
# Enforce full PCI address format: 0000:00:00.0
PCI_ADDR_PATTERN = re.compile(r'^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$')
# Driver names should be safe: alphanumeric, hyphens, underscores
DRIVER_PATTERN = re.compile(r'^[a-zA-Z0-9_\-]+$')

def validate_pci_addr(addr):
    if not PCI_ADDR_PATTERN.match(addr):
        raise ValueError(f"Invalid PCI address format: {addr}. Expected format: 0000:00:00.0")
    return addr

def validate_driver(driver):
    if not DRIVER_PATTERN.match(driver):
        raise ValueError(f"Invalid driver name: {driver}")
    return driver

def run_cmd(cmd_list):
    """Run command and return output. cmd_list must be a list of arguments."""
    try:
        # shell=False ensures arguments are not interpreted by shell
        result = subprocess.run(cmd_list, shell=False, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def write_to_file(path, content):
    """Securely write content to file"""
    try:
        with open(path, 'w') as f:
            f.write(content + '\n') # echo adds a newline
        return 0, "", ""
    except Exception as e:
        return 1, "", str(e)

def get_device_info(pci_addr):
    """Get detailed device information"""
    # lspci -s can take short or long address.
    ret, out, err = run_cmd(["lspci", "-s", pci_addr])
    if ret == 0 and out.strip():
        # Parse: 00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)
        parts = out.strip().split(': ', 2)
        if len(parts) >= 2:
            return parts[1].strip()
    return "Unknown device"

def get_ena_devices():
    """Get list of ENA network devices"""
    ret, out, err = run_cmd(["lspci", "-d", "1d0f:"])
    devices = []
    if ret != 0:
        return devices

    for line in out.strip().split('\n'):
        if line and 'Ethernet' in line:
            # line: 00:06.0 Ethernet controller: ...
            pci_addr = line.split()[0]
            full_addr = f"0000:{pci_addr}"
            desc = get_device_info(pci_addr)
            devices.append({'addr': full_addr, 'desc': desc, 'short_addr': pci_addr})
    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Use os.readlink instead of subprocess
    driver_path = f"/sys/bus/pci/devices/{pci_addr}/driver"
    try:
        if os.path.exists(driver_path):
            driver_link = os.readlink(driver_path)
            driver = os.path.basename(driver_link)
        else:
            driver = "none"
    except OSError:
        driver = "none"
    
    # Get interface name if available
    interface = ""
    net_path = f"/sys/bus/pci/devices/{pci_addr}/net/"
    try:
        if os.path.isdir(net_path):
            files = os.listdir(net_path)
            if files:
                interface = sorted(files)[0]
    except OSError:
        pass
    
    # Check if interface is active
    active = False
    if interface:
        ret, out, err = run_cmd(["ip", "link", "show", interface])
        if ret == 0 and "state UP" in out:
            active = True
    
    return driver, interface, active

def bind_device(pci_addr, driver):
    """Bind PCI device to specified driver using driver_override method"""
    # Security: Validate inputs
    pci_addr = validate_pci_addr(pci_addr)
    driver = validate_driver(driver)

    print(f"Binding {pci_addr} to {driver}")
    
    # Get current driver
    current_driver, _, _ = get_driver_info(pci_addr)
    
    if current_driver == driver:
        print(f"Device {pci_addr} already bound to {driver}")
        return True
    
    # Step 1: Unbind from current driver if bound
    if current_driver != "none" and current_driver != "unknown":
        print(f"  Unbinding from {current_driver}")
        ret, out, err = write_to_file(f"/sys/bus/pci/devices/{pci_addr}/driver/unbind", pci_addr)
        if ret != 0:
            print(f"  Warning: Failed to unbind from {current_driver}: {err}")
    
    # Step 2: Set driver override
    print(f"  Setting driver override to {driver}")
    ret, out, err = write_to_file(f"/sys/bus/pci/devices/{pci_addr}/driver_override", driver)
    if ret != 0:
        print(f"  Error: Failed to set driver override: {err}")
        return False
    
    # Step 3: For vfio-pci, ensure module is loaded and device ID is added
    if driver == "vfio-pci":
        print("  Loading vfio-pci module")
        run_cmd(["modprobe", "vfio-pci"])
        
        print("  Adding ENA device ID to vfio-pci")
        vfio_new_id_path = "/sys/bus/pci/drivers/vfio-pci/new_id"
        if os.path.exists(vfio_new_id_path):
            ret, out, err = write_to_file(vfio_new_id_path, "1d0f ec20")
            if ret != 0:
                print(f"  Warning: Failed to add device ID: {err}")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        iommu_path = "/sys/kernel/iommu_groups/"
        try:
            # Check if IOMMU groups exist and are effectively empty
            if not os.path.exists(iommu_path) or not os.listdir(iommu_path):
                print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
                write_to_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
        except OSError:
            pass
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    ret, out, err = write_to_file(f"/sys/bus/pci/drivers_probe", pci_addr)
    if ret != 0:
        print(f"  Error: Failed to probe device: {err}")
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
        try:
            success = bind_device(sys.argv[3], sys.argv[2])
            if not success:
                sys.exit(1)
        except ValueError as e:
            print(f"Error: {e}")
            sys.exit(1)
    elif sys.argv[1] == "--help" or sys.argv[1] == "-h":
        print("Usage:")
        print("  dpdk-devbind.py                    - Show device status")
        print("  dpdk-devbind.py -s|--status        - Show device status")
        print("  dpdk-devbind.py -b|--bind <driver> <pci_addr> - Bind device")
        print("  dpdk-devbind.py -h|--help          - Show this help")
    else:
        show_status()
