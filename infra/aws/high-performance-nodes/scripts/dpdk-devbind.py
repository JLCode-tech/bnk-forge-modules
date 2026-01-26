#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
# Optimized by Bolt: uses native os calls and avoids N+1 lspci queries
import subprocess
import sys
import os

def run_cmd(cmd):
    """Run shell command and return output"""
    try:
        # Ensure cmd is a list for shell=False
        if isinstance(cmd, str):
            cmd = cmd.split()
        result = subprocess.run(cmd, shell=False, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def write_to_file(path, content):
    """Write content to file (replaces echo > file)"""
    try:
        with open(path, 'w') as f:
            f.write(content + "\n") # echo adds newline
        return 0, "", ""
    except Exception as e:
        return 1, "", str(e)

def get_ena_devices():
    """Get list of ENA network devices"""
    # Use lspci -d 1d0f: to get all ENA devices with descriptions
    # Avoids N+1 calls to lspci -s for each device
    ret, out, err = run_cmd(["lspci", "-d", "1d0f:"])
    devices = []
    for line in out.strip().split('\n'):
        if line and 'Ethernet' in line:
            # Output format: 00:06.0 Ethernet controller: Amazon.com...
            parts = line.split(' ', 1)
            pci_addr = parts[0]
            full_addr = f"0000:{pci_addr}"

            # Parse description from the rest of the line
            desc = "Unknown device"
            if len(parts) > 1:
                desc_parts = parts[1].split(': ', 1)
                if len(desc_parts) > 1:
                    desc = desc_parts[1].strip()

            devices.append({'addr': full_addr, 'desc': desc, 'short_addr': pci_addr})
    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Get current driver using os.readlink
    driver = "none"
    try:
        path = os.readlink(f"/sys/bus/pci/devices/{pci_addr}/driver")
        driver = os.path.basename(path)
    except OSError:
        pass
    
    # Get interface name if available using os.listdir
    interface = ""
    try:
        files = os.listdir(f"/sys/bus/pci/devices/{pci_addr}/net/")
        if files:
            interface = files[0]
    except OSError:
        pass
    
    # Check if interface is active
    active = False
    if interface:
        # Must still use ip command for link status
        ret, out, err = run_cmd(["ip", "link", "show", interface])
        if ret == 0 and "state UP" in out:
            active = True
    
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
        ret, out, err = write_to_file("/sys/bus/pci/drivers/vfio-pci/new_id", "1d0f ec20")
        if ret != 0:
            print(f"  Warning: Failed to add device ID: {err}")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        # Optimization: use os.listdir instead of ls | wc -l
        try:
            iommu_groups = os.listdir("/sys/kernel/iommu_groups/")
            # . and .. are not included in os.listdir, so checking if empty or just not enough real groups
            # The original check was `ls | wc -l` <= 2 (which meant empty or only . and ..)
            # os.listdir returns names, so len(groups) == 0 means empty.
            if len(iommu_groups) == 0:
                print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
                write_to_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
        except OSError:
            # If directory doesn't exist, assume no IOMMU
            print("  Enabling unsafe NOIOMMU mode (no IOMMU groups found)")
            write_to_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    ret, out, err = write_to_file("/sys/bus/pci/drivers_probe", pci_addr)
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
