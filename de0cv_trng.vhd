-- ----------------------------------------------------------------------------
-- de0cv_trng.vhd   (top level)
--
-- DE0-CV / Cyclone V 5CEBA4F23C7N
--
-- Ring-oscillator TRNG: NUM_RINGS free-running ring oscillators (INV_PER_RING
-- NOT gates each), XORed together into one entropy signal, sampled by a
-- single D-flip-flop at 40 MHz, de-biased (von Neumann extractor), packed
-- into bytes and streamed continuously to the PC over the on-board
-- USB-Blaster cable via the JTAG UART (alt_jtag_atlantic), exactly as read
-- with `juart-terminal` on the host.
-- Follows B. Sunar, W.J. Martin, D.R. Stinson, IEEE Trans. Computers 56(1),
-- 2007 (114 rings x 13 inverters, XOR, 40 MHz sampling flip-flop,
-- post-processing) -- see knowledge/Material complementar 3.pdf, Figure 8.
--
--   CLOCK_50 : 50 MHz board clock (PIN_M9)
--   KEY(0)   : active-low reset   (PIN_U7)  -- press to re-lock the PLL / restart
--   LEDR(0)  : heartbeat (toggles once per exported byte)
--   LEDR(9)  : PLL lock indicator
-- ----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity de0cv_trng is
    generic (
        NUM_RINGS     : natural := 114;    -- number of ring oscillators
        INV_PER_RING  : natural := 13;     -- NOT gates per ring (must be odd)
        LOG2_TXFIFO   : natural := 12      -- 2**12 = 4096-byte JTAG TX FIFO
    );
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(0 downto 0);
        LEDR     : out std_logic_vector(9 downto 0)
    );
end entity de0cv_trng;

architecture rtl of de0cv_trng is

    ----------------------------------------------------------------------------
    -- CLOCK_50-domain reset synchroniser (button + power-up), feeds the PLL's
    -- async reset -- same shape as COUNTER_JTAG/de0cv_counter_jtag.vhd
    ----------------------------------------------------------------------------
    signal rst50    : std_logic := '1';
    signal rst50_sr : std_logic_vector(2 downto 0) := (others => '1');

    ----------------------------------------------------------------------------
    -- 40 MHz sampling clock
    ----------------------------------------------------------------------------
    signal clk40       : std_logic;
    signal pll_locked  : std_logic;

    -- clk40-domain reset: async assert (PLL unlocked), sync release
    signal rst40    : std_logic := '1';
    signal rst40_sr : std_logic_vector(2 downto 0) := (others => '1');

    ----------------------------------------------------------------------------
    -- ring oscillators -> XOR -> sampler -> packer -> JTAG UART
    ----------------------------------------------------------------------------
    signal ring_out     : std_logic_vector(NUM_RINGS - 1 downto 0);
    signal entropy_bit  : std_logic;
    signal sampled_bit  : std_logic := '0';

    -- von Neumann de-biasing ("Pos-processamento" in Figure 8)
    signal vn_bit   : std_logic;
    signal vn_valid : std_logic;

    signal s_data  : std_logic_vector(7 downto 0);
    signal s_valid : std_logic;
    signal s_ready : std_logic;

    signal heartbeat : std_logic := '0';

begin

    ----------------------------------------------------------------------------
    -- reset synchronisers
    ----------------------------------------------------------------------------
    reset50_proc : process (CLOCK_50)
    begin
        if rising_edge(CLOCK_50) then
            rst50_sr <= rst50_sr(1 downto 0) & (not KEY(0));
            rst50    <= rst50_sr(2);
        end if;
    end process reset50_proc;

    reset40_proc : process (clk40, pll_locked)
    begin
        if pll_locked = '0' then
            rst40_sr <= (others => '1');
            rst40    <= '1';
        elsif rising_edge(clk40) then
            rst40_sr <= rst40_sr(1 downto 0) & '0';
            rst40    <= rst40_sr(2);
        end if;
    end process reset40_proc;

    ----------------------------------------------------------------------------
    -- 50 MHz -> 40 MHz PLL
    ----------------------------------------------------------------------------
    u_pll : entity work.pll40
        port map (
            inclk50 => CLOCK_50,
            areset  => rst50,
            clk40   => clk40,
            locked  => pll_locked
        );

    ----------------------------------------------------------------------------
    -- NUM_RINGS free-running ring oscillators, each INV_PER_RING NOT gates
    ----------------------------------------------------------------------------
    gen_rings : for i in 0 to NUM_RINGS - 1 generate
        u_ring : entity work.ring_oscillator
            generic map (
                NUM_INV => INV_PER_RING
            )
            port map (
                enable  => not rst40,
                osc_out => ring_out(i)
            );
    end generate gen_rings;

    ----------------------------------------------------------------------------
    -- mix: XOR every ring output together into one entropy bit
    ----------------------------------------------------------------------------
    xor_reduce_proc : process (ring_out)
        variable v : std_logic;
    begin
        v := '0';
        for i in 0 to NUM_RINGS - 1 loop
            v := v xor ring_out(i);
        end loop;
        entropy_bit <= v;
    end process xor_reduce_proc;

    ----------------------------------------------------------------------------
    -- sample the mixed, free-running entropy signal at 40 MHz with a single
    -- D-flip-flop (deliberately unconditional -- this is the TRNG's actual
    -- output bit, not a controllable/gateable pipeline stage)
    ----------------------------------------------------------------------------
    sampler_proc : process (clk40)
    begin
        if rising_edge(clk40) then
            sampled_bit <= entropy_bit;
        end if;
    end process sampler_proc;

    ----------------------------------------------------------------------------
    -- de-bias (von Neumann extractor) -- see knowledge/Material complementar
    -- 3.pdf Sec. 2.5; the raw XOR-of-rings output is not a perfectly unbiased
    -- coin, so this is the "Pos-processamento" stage in the reference Figure 8
    ----------------------------------------------------------------------------
    --u_von_neumann : entity work.von_neumann
    --    port map (
    --        clk       => clk40,
    --        rst       => rst40,
		--				
    --        bit_in    => sampled_bit,
						
   --         bit_out   => vn_bit,
    --        bit_valid => vn_valid
     --   );
		
    ----------------------------------------------------------------------------
    -- pack de-biased bits into bytes, stream them to the PC over JTAG
    ----------------------------------------------------------------------------
    u_packer : entity work.trng_packer
        port map (
            clk       => clk40,
            rst       => rst40,
						
            -- bit_in    => vn_bit,
						bit_in 		=> sampled_bit,
            -- bit_valid => vn_valid,
						bit_valid	=> '1',
						
            m_data    => s_data,
            m_valid   => s_valid,
            m_ready   => s_ready
        );

    u_jtag : entity work.jtag_uart_tx
        generic map (
            LOG2_DEPTH => LOG2_TXFIFO
        )
        port map (
            clk     => clk40,
            rst     => rst40,
            s_data  => s_data,
            s_valid => s_valid,
            s_ready => s_ready
        );

    ----------------------------------------------------------------------------
    -- liveness indicators
    ----------------------------------------------------------------------------
    heartbeat_proc : process (clk40)
    begin
        if rising_edge(clk40) then
            if rst40 = '1' then
                heartbeat <= '0';
            elsif s_valid = '1' and s_ready = '1' then
                heartbeat <= not heartbeat;    -- toggles once per exported byte
            end if;
        end if;
    end process heartbeat_proc;

    LEDR(0)          <= heartbeat;
    LEDR(8 downto 1) <= (others => '0');
    LEDR(9)          <= pll_locked;

end architecture rtl;
