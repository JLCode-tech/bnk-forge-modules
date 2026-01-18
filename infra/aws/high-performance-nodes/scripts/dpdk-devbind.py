#!/usr/bin/env python3
# Simple DPDK device binding script for ENA interfaces
import subprocess
import sys
import os
import re

# Regex for PCI address validation
PCI_ADDR_REGEX = re.compile(r'^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9]$')

def validate_pci_addr(pci_addr):
    if not PCI_ADDR_REGEX.match(pci_addr):
        raise ValueError(f"Invalid PCI address format: {pci_addr}")
    return pci_addr

def run_cmd(cmd):
    """Run shell command and return output"""
    try:
        # Expect cmd to be a list for shell=False
        if isinstance(cmd, str):
            cmd = cmd.split()

        result = subprocess.run(cmd, shell=False, capture_output=True, text=True)
        return result.returncode, result.stdout, result.stderr
    except Exception as e:
        return 1, "", str(e)

def read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read().strip()
    except Exception:
        return ""

def write_file(path, content):
    try:
        with open(path, 'w') as f:
            f.write(content)
            # Ensure newline if not present, similar to echo
            if not content.endswith('\n'):
                f.write('\n')
        return True
    except Exception as e:
        return False

def get_device_info(pci_addr):
    """Get detailed device information"""
    try:
        validate_pci_addr(pci_addr)
        # Use short address for lspci -s if needed, or full address works too on modern lspci
        # Original script used pci_addr which was 00:06.0 inside get_ena_devices loop
        # But wait, get_ena_devices calls get_device_info with pci_addr from lspci -d 1d0f: output
        # which is 00:06.0
        # If we pass 0000:00:06.0 to lspci -s, it works.

        # We'll rely on lspci to give us the description
        ret, out, err = run_cmd(["lspci", "-s", pci_addr])
        if ret == 0 and out.strip():
            # Parse: 00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)
            parts = out.strip().split(': ', 2)
            if len(parts) >= 2:
                return parts[1].strip()
    except Exception:
        pass
    return "Unknown device"

def get_ena_devices():
    """Get list of ENA network devices"""
    devices = []
    pci_path = "/sys/bus/pci/devices"

    if os.path.exists(pci_path):
        try:
            # Sort explicitly for deterministic behavior
            all_devices = sorted(os.listdir(pci_path))

            for dev_name in all_devices:
                # dev_name is typically 0000:00:06.0
                vendor_path = os.path.join(pci_path, dev_name, "vendor")
                if not os.path.exists(vendor_path):
                    continue

                vendor = read_file(vendor_path)
                # ENA vendor ID is 0x1d0f
                if "1d0f" in vendor:
                    full_addr = dev_name
                    short_addr = dev_name[5:] if len(dev_name) > 5 else dev_name

                    # Get description using lspci (safe now)
                    desc = get_device_info(full_addr)

                    devices.append({'addr': full_addr, 'desc': desc, 'short_addr': short_addr})
        except Exception:
            pass

    return devices

def get_driver_info(pci_addr):
    """Get current driver and interface information"""
    # Get current driver
    driver = "none"
    driver_path = os.path.join("/sys/bus/pci/devices", pci_addr, "driver")
    if os.path.islink(driver_path):
        try:
            driver_link = os.readlink(driver_path)
            driver = os.path.basename(driver_link)
        except OSError:
            pass
    
    # Get interface name if available
    interface = ""
    net_path = os.path.join("/sys/bus/pci/devices", pci_addr, "net")
    if os.path.exists(net_path):
        try:
            nets = os.listdir(net_path)
            if nets:
                interface = sorted(nets)[0]
        except OSError:
            pass
    
    # Check if interface is active
    active = False
    if interface:
        operstate = read_file(f"/sys/class/net/{interface}/operstate")
        if operstate == "up":
            active = True
    
    return driver, interface, active

def bind_device(pci_addr, driver):
    """Bind PCI device to specified driver using driver_override method"""
    try:
        validate_pci_addr(pci_addr)
    except ValueError as e:
        print(f"Error: {e}")
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
        unbind_path = f"/sys/bus/pci/devices/{pci_addr}/driver/unbind"
        if not write_file(unbind_path, pci_addr):
            print(f"  Warning: Failed to unbind from {current_driver}")
    
    # Step 2: Set driver override
    print(f"  Setting driver override to {driver}")
    override_path = f"/sys/bus/pci/devices/{pci_addr}/driver_override"
    if not write_file(override_path, driver):
        print(f"  Error: Failed to set driver override")
        return False
    
    # Step 3: For vfio-pci, ensure module is loaded and device ID is added
    if driver == "vfio-pci":
        print("  Loading vfio-pci module")
        run_cmd(["modprobe", "vfio-pci"])
        
        print("  Adding ENA device ID to vfio-pci")
        write_file("/sys/bus/pci/drivers/vfio-pci/new_id", "1d0f ec20")
        
        # Enable unsafe NOIOMMU mode if IOMMU groups are empty
        iommu_path = "/sys/kernel/iommu_groups"
        iommu_count = 0
        if os.path.exists(iommu_path):
            try:
                iommu_count = len(os.listdir(iommu_path))
            except OSError:
                pass

        if iommu_count == 0:
            print("  Enabling unsafe NOIOMMU mode (no IOMMU detected)")
            write_file("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
    
    # Step 4: Probe the device to bind it
    print(f"  Probing device to bind to {driver}")
    if not write_file("/sys/bus/pci/drivers_probe", pci_addr):
        print(f"  Error: Failed to probe device")
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
