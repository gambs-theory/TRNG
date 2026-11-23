-- ----------------------------------------------------------------------------
-- von_neumann.vhd
--
-- The "Pos-processamento" block in Figure 8 of knowledge/Material complementar
-- 3.pdf, after the sampling flip-flop and before packing/export. Raw ring-
-- oscillator XOR output is never a perfectly unbiased coin (gate duty-cycle
-- asymmetry biases every ring the same way, and XOR-ing 114 of them does not
-- fully cancel a systematic, correlated bias) -- see PDF Sec. 2.5, "Remocao de
-- vies na saida do TRNG com extratores de aleatoriedade".
--
-- Classic von Neumann extractor: look at raw bits two at a time.
--   01 -> emit 0
--   10 -> emit 1
--   00, 11 -> discard, no output
-- This removes any static bias in the input (P(1) != 0.5) as long as
-- consecutive samples are not themselves correlated with each other, at the
-- cost of throwing away most raw bits (throughput ~= 2p(1-p) of the input
-- rate, <=25% even for an unbiased input). That is a non-issue here: raw
-- samples arrive at 40 MHz, far above anything alt_jtag_atlantic can export,
-- so this costs nothing against the achievable capture rate.
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity von_neumann is
    port (
        clk       : in  std_logic;
        rst       : in  std_logic;

        bit_in    : in  std_logic;    -- one raw sampled bit per clk edge

        bit_out   : out std_logic;    -- de-biased bit, valid when bit_valid='1'
        bit_valid : out std_logic     -- one-cycle pulse: a pair resolved
    );
end entity von_neumann;

architecture rtl of von_neumann is
    signal have_first : std_logic := '0';
    signal first_bit   : std_logic := '0';
begin

    process (clk)
    begin
        if rising_edge(clk) then
            bit_valid <= '0';    -- default; only pulses when a pair resolves

            if rst = '1' then
                have_first <= '0';

            elsif have_first = '0' then
                first_bit  <= bit_in;
                have_first <= '1';

            else
                have_first <= '0';
                if bit_in /= first_bit then
                    bit_out   <= first_bit;
                    bit_valid <= '1';
                end if;
                -- bit_in = first_bit ("00" or "11"): pair discarded, no output
            end if;
        end if;
    end process;

end architecture rtl;
