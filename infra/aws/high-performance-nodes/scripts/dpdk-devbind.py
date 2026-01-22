#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os
import re

def validate_pci_addr(pci_addr):
    """Validate PCI address format (0000:00:00.0)"""
    if not re.match(r'^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$', pci_addr):
        # Also allow short format if strictly alphanumeric (though script seems to expand/use full)
        # But looking at usage: line.split()[0] from lspci -d 1d0f: usually gives 00:06.0
        # The script constructs full_addr = f"0000:{pci_addr}"
        # So inputs might be short form.
        if re.match(r'^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]$', pci_addr):
             return f"0000:{pci_addr}"

        # If it is already full format but didn't match first regex? (covered)
        print(f"Error: Invalid PCI address format: {pci_addr}")
        return None
    return pci_addr

def validate_driver_name(driver):
    """Validate driver name (alphanumeric, hyphens, underscores)"""
    if not re.match(r'^[a-zA-Z0-9_-]+$', driver):
        print(f"Error: Invalid driver name: {driver}")
        return False
    return True

def run_command(cmd_list):
    """Run command safely without shell=True"""
    try:
        # Check if cmd_list is actually a list
        if not isinstance(cmd_list, list):
             return 1, "", "Command must be a list of strings"

        result = subprocess.run(cmd_list, shell=False, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def write_to_file(path, content):
    """Write content to file (echo replacement)"""
    try:
        with open(path, 'w') as f:
            f.write(content)
            # Some sysfs files expect a newline
            if not content.endswith('\n'):
                f.write('\n')
        return 0, "", ""
    except Exception as e:
        return 1, "", str(e)

def get_device_info(pci_addr):
    """Get detailed device information"""
    # lspci -s {pci_addr}
    ret, out, err = run_command(["lspci", "-s", pci_addr])
    if ret == 0 and out.strip():
        # Parse: 00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)
        parts = out.strip().split(': ', 2)
        if len(parts) >= 2:
            return parts[1].strip()
    return "Unknown device"

def get_ena_devices():
    """Get list of ENA network devices"""
    # lspci -d 1d0f:
    ret, out, err = run_command(["lspci", "-d", "1d0f:"])
    devices = []
    if ret == 0:
        for line in out.strip().split('\n'):
            if line and 'Ethernet' in line:
                pci_addr = line.split()[0]
                full_addr = f"0000:{pci_addr}"
                desc = get_device_info(pci_addr)
                devices.append({'addr': full_addr, 'desc': desc, 'short_addr': pci_addr})
    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Get current driver via readlink
    driver = "none"
    driver_path = f"/sys/bus/pci/devices/{pci_addr}/driver"
    if os.path.exists(driver_path):
        try:
            link = os.readlink(driver_path)
            driver = os.path.basename(link)
        except OSError:
            pass
    
    # Get interface name if available
    interface = ""
    net_path = f"/sys/bus/pci/devices/{pci_addr}/net/"
    if os.path.exists(net_path) and os.path.isdir(net_path):
        try:
            # os.listdir should return interfaces like eth0
            interfaces = os.listdir(net_path)
            # Filter and sort to be deterministic
            interfaces = sorted([i for i in interfaces if not i.startswith('.')])
            if interfaces:
                interface = interfaces[0]
        except OSError:
            pass
    
    # Check if interface is active
    active = False
    if interface:
        # ip link show {interface}
        ret, out, err = run_command(["ip", "link", "show", interface])
        if ret == 0 and "state UP" in out:
            active = True
    
    return driver, interface, active

def bind_device(pci_addr, driver):
    """Bind PCI device to specified driver using driver_override method"""

    # Validate inputs
    pci_addr = validate_pci_addr(pci_addr)
    if not pci_addr:
        return False

    if not validate_driver_name(driver):
        return False

    print(f"Binding {pci_addr} to {driver}")
    
    # Get current driver
    current_driver, _, _ = get_driver_info(pci_addr)
    
    if current_driver == driver:
        print(f"Device {pci_addr} already bound to {driver}")
        return True
    
    # Step 1: Unbind from current driver if bound
    if current_driver != "none":
        print(f"  Unbinding from {current_driver}")
        # echo {pci_addr} > /sys/bus/pci/devices/{pci_addr}/driver/unbind
        unbind_path = f"/sys/bus/pci/devices/{pci_addr}/driver/unbind"
        ret, _, err = write_to_file(unbind_path, pci_addr)
        if ret != 0:
            print(f"  Warning: Failed to unbind from {current_driver}: {err}")
    
    # Step 2: Set driver override
    print(f"  Setting driver override to {driver}")
    # echo {driver} > /sys/bus/pci/devices/{pci_addr}/driver_override
    override_path = f"/sys/bus/pci/devices/{pci_addr}/driver_override"
    ret, _, err = write_to_file(override_path, driver)
    if ret != 0:
        print(f"  Error: Failed to set driver override: {err}")
        return False
    
    # Step 3: For vfio-pci, ensure module is loaded and device ID is added
    if driver == "vfio-pci":
        print("  Loading vfio-pci module")
        run_command(["modprobe", "vfio-pci"])
        
        print("  Adding ENA device ID to vfio-pci")
        # echo '1d0f ec20' > /sys/bus/pci/drivers/vfio-pci/new_id
        # We need to be careful not to fail if it's already there (write might fail with EEXIST)
        # Just try to write
        ret, _, err = write_to_file("/sys/bus/pci/drivers/vfio-pci/new_id", "1d0f ec20")
        if ret != 0:
             # Only warn if we really failed, but usually EEXIST is fine.
             # However, since we can't easily distinguish EEXIST from others with this helper,
             # we'll print the warning as per original behavior.
             print(f"  Warning: Failed to add device ID: {err}")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        # ls /sys/kernel/iommu_groups/ | wc -l
        iommu_groups_path = "/sys/kernel/iommu_groups/"
        group_count = 0
        if os.path.exists(iommu_groups_path) and os.path.isdir(iommu_groups_path):
             try:
                 # Count entries
                 entries = os.listdir(iommu_groups_path)
                 group_count = len(entries)
             except OSError:
                 pass
        else:
             # If directory doesn't exist, assume no IOMMU
             group_count = -1

        # If count is small (usually just empty or non-existent means no IOMMU support configured)
        # Original logic: wc -l <= 2 (which counts . and .. if ls -a or just output lines)
        # ls on linux doesn't show . and .. by default.
        # So wc -l was counting actual visible files.
        # If group_count is 0, it means no groups.

        if group_count <= 0:
            print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
            write_to_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    # echo {pci_addr} > /sys/bus/pci/drivers_probe
    ret, _, err = write_to_file("/sys/bus/pci/drivers_probe", pci_addr)
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
