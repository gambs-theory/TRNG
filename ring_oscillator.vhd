-- ----------------------------------------------------------------------------
-- ring_oscillator.vhd
--
-- One ring oscillator: NUM_INV NOT gates (must be odd) wired in a closed loop.
-- With an odd number of inversions the loop has no stable state, so it free-
-- runs, toggling continuously at a rate set by the gate/routing delay of one
-- pass around the ring -- jitter in that delay (thermal/supply/1-over-f noise)
-- is the actual entropy source for the TRNG built on top of this.
--
-- 'enable' is folded into the first stage (same trick as the 3-inverter demo
-- in ../RingOsc/ring_osc.vhd, generalised to NUM_INV stages): with enable='1'
-- stage 0 is a plain inverter and the ring oscillates; with enable='0' stage 0
-- is forced to '1', breaking the loop so every ring starts from the same known
-- state instead of a power-up race.
--
-- KEEP on every stage is required: without it, synthesis sees a chain of NOT
-- gates whose output is unused by the rest of the netlist (until it reaches
-- the XOR tree) and folds/removes the "redundant" inverters, collapsing the
-- ring to nothing.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity ring_oscillator is
    generic (
        NUM_INV : natural := 13    -- inverter stages; must be odd
    );
    port (
        enable  : in  std_logic;
        osc_out : out std_logic
    );
end entity ring_oscillator;

architecture rtl of ring_oscillator is

    signal inv : std_logic_vector(NUM_INV - 1 downto 0);

    attribute KEEP : boolean;
    attribute KEEP of inv : signal is true;

begin

    -- stage 0: NAND(enable, last stage) -- inverter when enable='1',
    -- forces '1' and breaks the feedback loop when enable='0'
    inv(0) <= not (enable and inv(NUM_INV - 1));

    gen_chain : for i in 1 to NUM_INV - 1 generate
        inv(i) <= not inv(i - 1);
    end generate gen_chain;

    osc_out <= inv(NUM_INV - 1);

end architecture rtl;
