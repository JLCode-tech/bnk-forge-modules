import unittest
from unittest.mock import MagicMock, patch, mock_open
import importlib.util
import os
import sys

# Load the module
MODULE_PATH = "infra/aws/high-performance-nodes/scripts/dpdk-devbind.py"
spec = importlib.util.spec_from_file_location("dpdk_devbind", MODULE_PATH)
dpdk_devbind = importlib.util.module_from_spec(spec)
sys.modules["dpdk_devbind"] = dpdk_devbind
spec.loader.exec_module(dpdk_devbind)

class TestDpdkDevbind(unittest.TestCase):

    @patch('subprocess.run')
    def test_run_cmd_list(self, mock_run):
        # Testing list input
        mock_run.return_value.returncode = 0
        mock_run.return_value.stdout = "output"
        mock_run.return_value.stderr = ""

        ret, out, err = dpdk_devbind.run_cmd(["some", "command"])

        self.assertEqual(ret, 0)
        self.assertEqual(out, "output")
        mock_run.assert_called_with(["some", "command"], shell=False, capture_output=True, text=True)

    def test_validate_pci_addr(self):
        dpdk_devbind.validate_pci_addr("0000:00:06.0")
        with self.assertRaises(ValueError):
            dpdk_devbind.validate_pci_addr("invalid")
        with self.assertRaises(ValueError):
            dpdk_devbind.validate_pci_addr("00:06.0") # Short not allowed by regex, must be full

    def test_get_device_info(self):
        with patch('dpdk_devbind.run_cmd') as mock_run_cmd:
            mock_run_cmd.return_value = (0, "00:06.0 Ethernet controller: Amazon.com, Inc. Elastic Network Adapter (ENA)", "")
            desc = dpdk_devbind.get_device_info("0000:00:06.0")
            self.assertEqual(desc, "Amazon.com, Inc. Elastic Network Adapter (ENA)")
            mock_run_cmd.assert_called_with(["lspci", "-s", "0000:00:06.0"])

    @patch('os.path.islink')
    @patch('os.readlink')
    @patch('os.path.exists')
    @patch('os.listdir')
    @patch('builtins.open', new_callable=mock_open, read_data="up\n")
    def test_get_driver_info(self, mock_file, mock_listdir, mock_exists, mock_readlink, mock_islink):
        mock_islink.return_value = True
        mock_readlink.return_value = "../../drivers/ena"
        mock_exists.return_value = True
        mock_listdir.return_value = ["eth0"]

        driver, interface, active = dpdk_devbind.get_driver_info("0000:00:06.0")

        self.assertEqual(driver, "ena")
        self.assertEqual(interface, "eth0")
        self.assertTrue(active)

        mock_readlink.assert_called_with("/sys/bus/pci/devices/0000:00:06.0/driver")

    @patch('dpdk_devbind.write_file')
    @patch('dpdk_devbind.get_driver_info')
    @patch('dpdk_devbind.run_cmd')
    @patch('os.path.exists')
    @patch('os.listdir')
    def test_bind_device_vfio(self, mock_listdir, mock_exists, mock_run_cmd, mock_get_driver, mock_write):
        # Setup
        mock_get_driver.side_effect = [
            ("none", "", False), # Initial state
            ("vfio-pci", "", False) # Final state
        ]
        mock_write.return_value = True
        mock_run_cmd.return_value = (0, "", "")

        mock_exists.return_value = True
        mock_listdir.return_value = [] # Empty IOMMU groups -> use safe NOIOMMU

        success = dpdk_devbind.bind_device("0000:00:06.0", "vfio-pci")

        self.assertTrue(success)

        # Verify calls
        # 1. driver_override
        mock_write.assert_any_call("/sys/bus/pci/devices/0000:00:06.0/driver_override", "vfio-pci")
        # 2. modprobe
        mock_run_cmd.assert_called_with(["modprobe", "vfio-pci"])
        # 3. new_id
        mock_write.assert_any_call("/sys/bus/pci/drivers/vfio-pci/new_id", "1d0f ec20")
        # 4. unsafe noiommu (because listdir returned [])
        mock_write.assert_any_call("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", "1")
        # 5. probe
        mock_write.assert_any_call("/sys/bus/pci/drivers_probe", "0000:00:06.0")

if __name__ == '__main__':
    unittest.main()
