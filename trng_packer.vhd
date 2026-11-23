-- ----------------------------------------------------------------------------
-- trng_packer.vhd
--
-- Packs the de-biased TRNG bit stream (from von_neumann.vhd) into bytes for
-- jtag_uart_tx, using the same busy/valid/ready shape as hex_printer.vhd in
-- ../COUNTER_JTAG:
--
--   * whenever bit_valid='1', shift bit_in into a shift register, MSB first;
--   * once 8 bits are collected, hold the byte on m_data/m_valid until
--     jtag_uart_tx (or its internal alt_jtag_atlantic TX FIFO) accepts it;
--   * while a byte is pending, incoming bits are simply not accumulated --
--     von_neumann.vhd keeps producing/discarding bit pairs on its own
--     regardless, so this only ever discards whole samples, never tears a
--     byte.
--
-- alt_jtag_atlantic throughput over the on-board USB-Blaster is well below
-- the bit rate von_neumann.vhd can produce (itself already well below the
-- raw 40 Mbit/s sampler rate), so in steady state this packer spends most of
-- its time in the "pending" state -- expected and harmless.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity trng_packer is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        bit_in    : in  std_logic;   -- de-biased bit, sampled when bit_valid='1'
        bit_valid : in  std_logic;

        -- byte-stream master towards jtag_uart_tx
        m_data  : out std_logic_vector(7 downto 0);
        m_valid : out std_logic;
        m_ready : in  std_logic
    );
end entity trng_packer;

architecture rtl of trng_packer is

    signal shreg    : std_logic_vector(7 downto 0) := (others => '0');
    signal bit_idx  : integer range 0 to 7 := 0;
    signal pending  : std_logic := '0';

begin

    m_data  <= shreg;
    m_valid <= pending;

    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                shreg   <= (others => '0');
                bit_idx <= 0;
                pending <= '0';

            elsif pending = '1' then
                if m_ready = '1' then          -- byte accepted this cycle
                    pending <= '0';
                end if;

            elsif bit_valid = '1' then          -- accumulating a new byte
                shreg <= shreg(6 downto 0) & bit_in;
                if bit_idx = 7 then
                    bit_idx <= 0;
                    pending <= '1';
                else
                    bit_idx <= bit_idx + 1;
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
