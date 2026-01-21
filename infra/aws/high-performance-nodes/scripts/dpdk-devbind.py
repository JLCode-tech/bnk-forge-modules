#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os

def run_cmd(cmd):
    """Run shell command and return output"""
    try:
        # Support list args for shell=False
        use_shell = isinstance(cmd, str)
        result = subprocess.run(cmd, shell=use_shell, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def get_device_info(pci_addr):
    """Get detailed device information"""
    ret, out, err = run_cmd(["lspci", "-s", pci_addr])
    if ret == 0 and out.strip():
        # Parse: 00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)
        parts = out.strip().split(': ', 2)
        if len(parts) >= 2:
            return parts[1].strip()
    return "Unknown device"

def get_ena_devices():
    """Get list of ENA network devices"""
    # Use lspci to find devices and get descriptions in one pass
    ret, out, err = run_cmd(["lspci", "-d", "1d0f:"])
    devices = []
    for line in out.strip().split('\n'):
        if line and 'Ethernet' in line:
            parts = line.split()
            pci_addr = parts[0]
            full_addr = f"0000:{pci_addr}"

            # Extract description from the line itself to avoid N+1 lspci calls
            # Format: 00:06.0 Ethernet controller: ...
            desc_parts = line.split(': ', 2)
            desc = desc_parts[1].strip() if len(desc_parts) >= 2 else "Unknown device"

            devices.append({'addr': full_addr, 'desc': desc, 'short_addr': pci_addr})
    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Get current driver
    driver = "none"
    driver_path = f"/sys/bus/pci/devices/{pci_addr}/driver"
    if os.path.islink(driver_path):
        try:
            target = os.readlink(driver_path)
            driver = os.path.basename(target)
        except OSError:
            pass
    
    # Get interface name if available
    interface = ""
    net_path = f"/sys/bus/pci/devices/{pci_addr}/net"
    if os.path.isdir(net_path):
        try:
            interfaces = os.listdir(net_path)
            if interfaces:
                interface = interfaces[0]
        except OSError:
            pass
    
    # Check if interface is active
    active = False
    if interface:
        try:
            # Check operstate if available, otherwise assume active if link exists
            operstate_path = f"/sys/class/net/{interface}/operstate"
            if os.path.exists(operstate_path):
                with open(operstate_path, "r") as f:
                    state = f.read().strip()
                    active = (state == "up")
        except OSError:
            pass

    return driver, interface, active

def write_file(path, content):
    """Helper to write to sysfs file"""
    try:
        with open(path, "w") as f:
            f.write(content)
            # Some sysfs files require newline
            if not content.endswith('\n'):
                f.write('\n')
        return True, ""
    except Exception as e:
        return False, str(e)

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
        success, err = write_file(f"/sys/bus/pci/devices/{pci_addr}/driver/unbind", pci_addr)
        if not success:
            # It might have been unbound in parallel or just failed.
            # We continue but warn.
            print(f"  Warning: Failed to unbind from {current_driver}: {err}")
    
    # Step 2: Set driver override
    print(f"  Setting driver override to {driver}")
    success, err = write_file(f"/sys/bus/pci/devices/{pci_addr}/driver_override", driver)
    if not success:
        print(f"  Error: Failed to set driver override: {err}")
        return False
    
    # Step 3: For vfio-pci, ensure module is loaded and device ID is added
    if driver == "vfio-pci":
        print("  Loading vfio-pci module")
        run_cmd(["modprobe", "vfio-pci"])
        
        print("  Adding ENA device ID to vfio-pci")
        # We use write_file for this too.
        success, err = write_file("/sys/bus/pci/drivers/vfio-pci/new_id", "1d0f ec20")
        if not success:
             print(f"  Warning: Failed to add device ID: {err}")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        iommu_path = "/sys/kernel/iommu_groups"
        group_count = 0
        if os.path.isdir(iommu_path):
             group_count = len(os.listdir(iommu_path))

        # If directory exists but is empty (or only . .. which listdir doesn't show), count is 0.
        # Original logic was: `ls | wc -l` <= 2.
        # If no groups, enable unsafe mode.

        if not os.path.exists(iommu_path) or group_count == 0:
             print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
             write_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    success, err = write_file("/sys/bus/pci/drivers_probe", pci_addr)
    if not success:
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
