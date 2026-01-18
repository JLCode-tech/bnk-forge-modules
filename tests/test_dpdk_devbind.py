import unittest
from unittest.mock import patch, MagicMock, mock_open
import sys
import os
import importlib.util

# Load the module
spec = importlib.util.spec_from_file_location("dpdk_devbind", "infra/aws/high-performance-nodes/scripts/dpdk-devbind.py")
dpdk_devbind = importlib.util.module_from_spec(spec)
sys.modules["dpdk_devbind"] = dpdk_devbind
spec.loader.exec_module(dpdk_devbind)

class TestDpdkDevbind(unittest.TestCase):

    @patch('os.readlink')
    @patch('os.listdir')
    @patch('os.path.exists')
    @patch('builtins.open', new_callable=mock_open, read_data="up")
    def test_get_driver_info(self, mock_file, mock_exists, mock_listdir, mock_readlink):
        mock_readlink.return_value = "/sys/bus/pci/drivers/ena"
        mock_exists.return_value = True
        mock_listdir.return_value = ["eth0"]

        driver, interface, active = dpdk_devbind.get_driver_info("0000:00:06.0")

        self.assertEqual(driver, "ena")
        self.assertEqual(interface, "eth0")
        self.assertTrue(active)

        mock_readlink.assert_called_with("/sys/bus/pci/devices/0000:00:06.0/driver")
        mock_listdir.assert_called_with("/sys/bus/pci/devices/0000:00:06.0/net/")
        mock_file.assert_called_with("/sys/class/net/eth0/operstate", 'r')

    @patch('dpdk_devbind.get_driver_info')
    @patch('builtins.open', new_callable=mock_open)
    @patch('dpdk_devbind.run_cmd')
    @patch('os.listdir')
    def test_bind_device(self, mock_listdir, mock_run_cmd, mock_file, mock_get_info):
        # Initial state: bound to ena
        mock_get_info.side_effect = [("ena", "eth0", True), ("vfio-pci", "", False)]
        mock_run_cmd.return_value = (0, "", "") # Success for modprobe
        mock_listdir.return_value = [] # Empty IOMMU groups

        success = dpdk_devbind.bind_device("0000:00:06.0", "vfio-pci")

        self.assertTrue(success)

        # Verify file opens
        mock_file.assert_any_call("/sys/bus/pci/devices/0000:00:06.0/driver/unbind", 'w')
        mock_file.assert_any_call("/sys/bus/pci/devices/0000:00:06.0/driver_override", 'w')
        mock_file.assert_any_call("/sys/bus/pci/drivers/vfio-pci/new_id", 'w')
        mock_file.assert_any_call("/sys/module/vfio/parameters/enable_unsafe_noiommu_mode", 'w')
        mock_file.assert_any_call("/sys/bus/pci/drivers_probe", 'w')

        # Verify writes with newlines
        handle = mock_file()
        handle.write.assert_any_call("0000:00:06.0\n") # Unbind and Probe
        handle.write.assert_any_call("vfio-pci\n") # Driver override
        handle.write.assert_any_call("1d0f ec20\n") # New ID
        handle.write.assert_any_call("1\n") # Unsafe NOIOMMU

if __name__ == '__main__':
    unittest.main()
