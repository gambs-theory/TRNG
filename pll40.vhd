-- ----------------------------------------------------------------------------
-- pll40.vhd
--
-- Thin wrapper around Intel's ALTPLL megafunction: 50 MHz board clock in,
-- exactly 40 MHz out (multiply by 4, divide by 5), for the sampling
-- D-flip-flop. Everything downstream of the ring oscillators (sampler, byte
-- packer, jtag_uart_tx) runs from this clock, so there is only one clock
-- boundary to synchronise across: CLOCK_50 -> clk40 (handled by the caller's
-- reset synchroniser), not one per stage.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity pll40 is
    port (
        inclk50 : in  std_logic;   -- 50 MHz reference (CLOCK_50)
        areset  : in  std_logic;   -- async reset, high
        clk40   : out std_logic;   -- 40 MHz output
        locked  : out std_logic
    );
end entity pll40;

architecture rtl of pll40 is
    -- WIDTH_CLOCK defaults to 6 (CLK0..CLK5); only CLK0 is actually used, the
    -- rest are left unconnected and get optimized away during synthesis.
    -- (WIDTH_CLOCK=1 looks tempting to avoid that, but ALTPLL's internal
    -- clearbox model unconditionally references clk[1..4] in one of its
    -- generate branches and fails to elaborate below WIDTH_CLOCK=6.)
    signal clk_vec : std_logic_vector(5 downto 0);
begin
		-- altpll - Quartus's IP
    u_altpll : altpll
        generic map (
            intended_device_family => "Cyclone V",
            operation_mode         => "NORMAL",
            inclk0_input_frequency => 20000,   -- 1 / 50 MHz, in ps
            clk0_divide_by         => 5,
            clk0_multiply_by       => 4        -- 50 MHz * 4 / 5 = 40 MHz
        )
        port map (
            inclk  => (0 => inclk50, 1 => '0'),
            areset => areset,
            clk    => clk_vec,
            locked => locked
        );

    clk40 <= clk_vec(0);

end architecture rtl;
