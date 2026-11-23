-- ----------------------------------------------------------------------------
-- jtag_uart_tx.vhd
--
-- Thin wrapper around Intel's undocumented "alt_jtag_atlantic" megafunction.
-- alt_jtag_atlantic IS the JTAG-Atlantic SLD node that the host tools
-- "juart-terminal" / "nios2-terminal" talk to over the (on-board) USB-Blaster.
-- The full "JTAG UART" IP is just this node plus an Avalon-MM register wrapper
-- for a CPU; we don't need the CPU, so we drive the node directly.
--
-- This wrapper exposes a plain byte-stream SINK:
--     * put a byte on  s_data
--     * hold           s_valid = '1'
--     * the byte is consumed on a rising clk edge when s_valid='1' AND s_ready='1'
-- Anything pushed in here comes out on the PC side of the JTAG UART.
--
-- RX (PC -> FPGA) is not used in this demo; those ports are tied off.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity jtag_uart_tx is
    generic (
        INSTANCE_ID : integer := 0;   -- shows up as the node instance id
        LOG2_DEPTH  : integer := 6     -- 2**6 = 64-byte FIFOs inside the core
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;                       -- active-high

        s_data  : in  std_logic_vector(7 downto 0);    -- byte to send to PC
        s_valid : in  std_logic;                       -- '1' => s_data is valid
        s_ready : out std_logic                        -- '1' => byte taken this cycle
    );
end entity jtag_uart_tx;

architecture rtl of jtag_uart_tx is

    -- Port list of the encrypted megafunction (libraries/megafunctions/alt_jtag_atlantic.v)
    --   r_* : data read by the host  (FPGA -> PC)
    --   t_* : data transmitted by the host (PC -> FPGA)
    component alt_jtag_atlantic is
        generic (
            INSTANCE_ID             : integer;
            LOG2_RXFIFO_DEPTH       : integer;
            LOG2_TXFIFO_DEPTH       : integer;
            SLD_AUTO_INSTANCE_INDEX : string
        );
        port (
            clk     : in  std_logic;
            rst_n   : in  std_logic;
            r_dat   : in  std_logic_vector(7 downto 0);
            r_val   : in  std_logic;
            r_ena   : out std_logic;
            t_dat   : out std_logic_vector(7 downto 0);
            t_dav   : in  std_logic;
            t_ena   : out std_logic;
            t_pause : out std_logic
        );
    end component alt_jtag_atlantic;

    signal rst_n : std_logic;

begin

    rst_n <= not rst;

    u_atlantic : alt_jtag_atlantic
        generic map (
            INSTANCE_ID             => INSTANCE_ID,
            LOG2_RXFIFO_DEPTH       => LOG2_DEPTH,
            LOG2_TXFIFO_DEPTH       => LOG2_DEPTH,
            SLD_AUTO_INSTANCE_INDEX => "YES"
        )
        port map (
            clk     => clk,
            rst_n   => rst_n,
            r_dat   => s_data,     -- FPGA -> PC byte
            r_val   => s_valid,    -- we have a byte
            r_ena   => s_ready,    -- core accepts it this cycle
            t_dat   => open,       -- PC -> FPGA (unused)
            t_dav   => '1',        -- always willing to sink host keystrokes
            t_ena   => open,
            t_pause => open
        );

end architecture rtl;
