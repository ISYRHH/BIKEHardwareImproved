----------------------------------------------------------------------------------
-- Simple parameterizable Comba (carry-less) multiplier
-- Produces the carry-less product of two WIDTH-bit operands
-- Output width is 2*WIDTH-1 bits (degree 2*WIDTH-2), returned as vector (2*WIDTH-1 DOWNTO 0)
-- This is a combinational implementation intended as a leaf (Comba) multiplier.
----------------------------------------------------------------------------------
LIBRARY IEEE;
    USE IEEE.STD_LOGIC_1164.ALL;
    USE IEEE.NUMERIC_STD.ALL;

ENTITY CombaMul IS
    GENERIC (
        WIDTH : NATURAL := 32
    );
    PORT (
        A   : IN  STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
        B   : IN  STD_LOGIC_VECTOR(WIDTH-1 DOWNTO 0);
        R   : OUT STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0)
    );
END ENTITY;

ARCHITECTURE rtl OF CombaMul IS
BEGIN
    -- Combinational carry-less multiplication (schoolbook/Comba schedule)
    comb_process: PROCESS(A, B)
        VARIABLE tmp : STD_LOGIC_VECTOR(2*WIDTH-2 DOWNTO 0);
    BEGIN
        tmp := (OTHERS => '0');
        FOR i IN 0 TO WIDTH-1 LOOP
            IF A(i) = '1' THEN
                FOR j IN 0 TO WIDTH-1 LOOP
                    -- XOR-add the partial product bit into the corresponding position
                    IF B(j) = '1' THEN
                        tmp(i + j) := not tmp(i + j); -- toggle bit (XOR with '1')
                    END IF;
                END LOOP;
            END IF;
        END LOOP;
        R <= tmp;
    END PROCESS comb_process;

END ARCHITECTURE;
