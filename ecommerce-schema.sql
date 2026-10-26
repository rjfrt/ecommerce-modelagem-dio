-- =====================================================
-- E-commerce | Esquema lógico refinado (MySQL 8.0.16+)
-- Refinamentos: Cliente PF/PJ (exclusivo), múltiplas formas
-- de pagamento e entrega com status + código de rastreio
-- =====================================================
CREATE DATABASE IF NOT EXISTS ecommerce;
USE ecommerce;

-- ---------- CLIENTE (supertipo) ----------
CREATE TABLE cliente (
    id_cliente    INT AUTO_INCREMENT PRIMARY KEY,
    tipo_cliente  CHAR(2) NOT NULL,                -- discriminador: 'PF' ou 'PJ'
    email         VARCHAR(120) NOT NULL UNIQUE,
    telefone      VARCHAR(20),
    data_cadastro DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_tipo_cliente CHECK (tipo_cliente IN ('PF','PJ')),
    -- chave alternativa usada pelas FKs compostas dos subtipos
    CONSTRAINT uq_cliente_tipo UNIQUE (id_cliente, tipo_cliente)
);

-- ---------- SUBTIPO PF ----------
CREATE TABLE cliente_pf (
    id_cliente      INT PRIMARY KEY,
    tipo_cliente    CHAR(2) NOT NULL DEFAULT 'PF',
    nome            VARCHAR(60) NOT NULL,
    sobrenome       VARCHAR(60) NOT NULL,
    cpf             CHAR(11) NOT NULL UNIQUE,
    data_nascimento DATE,
    CONSTRAINT chk_pf_tipo CHECK (tipo_cliente = 'PF'),
    CONSTRAINT fk_pf_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente)
);

-- ---------- SUBTIPO PJ ----------
CREATE TABLE cliente_pj (
    id_cliente         INT PRIMARY KEY,
    tipo_cliente       CHAR(2) NOT NULL DEFAULT 'PJ',
    razao_social       VARCHAR(120) NOT NULL,
    nome_fantasia      VARCHAR(120),
    cnpj               CHAR(14) NOT NULL UNIQUE,
    inscricao_estadual VARCHAR(20),
    CONSTRAINT chk_pj_tipo CHECK (tipo_cliente = 'PJ'),
    CONSTRAINT fk_pj_cliente FOREIGN KEY (id_cliente, tipo_cliente)
        REFERENCES cliente (id_cliente, tipo_cliente)
);

-- ---------- ENDEREÇO ----------
CREATE TABLE endereco (
    id_endereco INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente  INT NOT NULL,
    logradouro  VARCHAR(120) NOT NULL,
    numero      VARCHAR(10),
    complemento VARCHAR(60),
    bairro      VARCHAR(60),
    cidade      VARCHAR(60) NOT NULL,
    uf          CHAR(2) NOT NULL,
    cep         CHAR(8) NOT NULL,
    CONSTRAINT fk_end_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
        ON DELETE CASCADE,
    CONSTRAINT uq_end_cliente UNIQUE (id_endereco, id_cliente)
);

-- ---------- FORMA DE PAGAMENTO (N por cliente) ----------
-- Nunca armazenar número completo/CVV: só dados não sensíveis.
CREATE TABLE forma_pagamento (
    id_forma_pagamento INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente         INT NOT NULL,
    tipo               ENUM('CARTAO_CREDITO','CARTAO_DEBITO','PIX','BOLETO') NOT NULL,
    apelido            VARCHAR(40),
    bandeira           VARCHAR(20),
    ultimos_digitos    CHAR(4),
    validade           CHAR(5),                    -- MM/AA
    chave_pix          VARCHAR(80),
    principal          BOOLEAN NOT NULL DEFAULT FALSE,
    ativo              BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_fp_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente)
        ON DELETE CASCADE,
    CONSTRAINT uq_fp_cliente UNIQUE (id_forma_pagamento, id_cliente)
);

-- ---------- PRODUTO ----------
CREATE TABLE produto (
    id_produto         INT AUTO_INCREMENT PRIMARY KEY,
    nome               VARCHAR(100) NOT NULL,
    categoria          VARCHAR(40),
    descricao          VARCHAR(255),
    valor              DECIMAL(10,2) NOT NULL,
    quantidade_estoque INT NOT NULL DEFAULT 0,
    CONSTRAINT chk_prod_valor CHECK (valor > 0),
    CONSTRAINT chk_prod_estoque CHECK (quantidade_estoque >= 0)
);

-- ---------- PEDIDO ----------
CREATE TABLE pedido (
    id_pedido     INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente    INT NOT NULL,
    id_endereco   INT NOT NULL,
    status_pedido ENUM('ABERTO','AGUARDANDO_PAGAMENTO','PAGO','CANCELADO') NOT NULL DEFAULT 'ABERTO',
    frete         DECIMAL(10,2) NOT NULL DEFAULT 0,
    data_pedido   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ped_cliente FOREIGN KEY (id_cliente) REFERENCES cliente (id_cliente),
    -- garante que o endereço de entrega pertence ao mesmo cliente do pedido
    CONSTRAINT fk_ped_endereco FOREIGN KEY (id_endereco, id_cliente)
        REFERENCES endereco (id_endereco, id_cliente),
    CONSTRAINT uq_ped_cliente UNIQUE (id_pedido, id_cliente)
);

CREATE TABLE item_pedido (
    id_pedido      INT NOT NULL,
    id_produto     INT NOT NULL,
    quantidade     INT NOT NULL,
    preco_unitario DECIMAL(10,2) NOT NULL,         -- preço congelado no momento da compra
    PRIMARY KEY (id_pedido, id_produto),
    CONSTRAINT chk_item_qtd CHECK (quantidade > 0),
    CONSTRAINT fk_item_pedido FOREIGN KEY (id_pedido) REFERENCES pedido (id_pedido)
        ON DELETE CASCADE,
    CONSTRAINT fk_item_produto FOREIGN KEY (id_produto) REFERENCES produto (id_produto)
);

-- ---------- PAGAMENTO DO PEDIDO (permite dividir em várias formas) ----------
CREATE TABLE pedido_pagamento (
    id_pedido_pagamento INT AUTO_INCREMENT PRIMARY KEY,
    id_pedido           INT NOT NULL,
    id_cliente          INT NOT NULL,
    id_forma_pagamento  INT NOT NULL,
    valor               DECIMAL(10,2) NOT NULL,
    parcelas            TINYINT NOT NULL DEFAULT 1,
    status_pagamento    ENUM('PENDENTE','APROVADO','RECUSADO','ESTORNADO') NOT NULL DEFAULT 'PENDENTE',
    CONSTRAINT chk_pp_valor CHECK (valor > 0),
    -- pedido e forma de pagamento precisam ser do MESMO cliente
    CONSTRAINT fk_pp_pedido FOREIGN KEY (id_pedido, id_cliente)
        REFERENCES pedido (id_pedido, id_cliente),
    CONSTRAINT fk_pp_forma FOREIGN KEY (id_forma_pagamento, id_cliente)
        REFERENCES forma_pagamento (id_forma_pagamento, id_cliente)
);

-- ---------- ENTREGA (status + código de rastreio) ----------
CREATE TABLE entrega (
    id_entrega      INT AUTO_INCREMENT PRIMARY KEY,
    id_pedido       INT NOT NULL,
    transportadora  VARCHAR(60),
    codigo_rastreio VARCHAR(30) UNIQUE,            -- NULL até a postagem
    status_entrega  ENUM('AGUARDANDO_ENVIO','EM_SEPARACAO','POSTADO','EM_TRANSITO',
                         'SAIU_PARA_ENTREGA','ENTREGUE','DEVOLVIDO','CANCELADA')
                    NOT NULL DEFAULT 'AGUARDANDO_ENVIO',
    data_envio      DATETIME,
    data_previsao   DATE,
    data_entrega    DATETIME,
    CONSTRAINT fk_ent_pedido FOREIGN KEY (id_pedido) REFERENCES pedido (id_pedido),
    -- após a postagem, o código de rastreio é obrigatório
    CONSTRAINT chk_ent_rastreio CHECK (
        status_entrega IN ('AGUARDANDO_ENVIO','EM_SEPARACAO','CANCELADA')
        OR codigo_rastreio IS NOT NULL
    )
);

-- Histórico de eventos da entrega (linha do tempo do rastreio)
CREATE TABLE entrega_historico (
    id_evento      INT AUTO_INCREMENT PRIMARY KEY,
    id_entrega     INT NOT NULL,
    status_entrega VARCHAR(20) NOT NULL,
    localizacao    VARCHAR(100),
    data_evento    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_hist_entrega FOREIGN KEY (id_entrega) REFERENCES entrega (id_entrega)
        ON DELETE CASCADE
);

-- =====================================================
-- DADOS DE EXEMPLO
-- =====================================================
INSERT INTO cliente (id_cliente, tipo_cliente, email, telefone) VALUES
 (1,'PF','rian@email.com','46999990001'),
 (2,'PJ','contato@techparts.com','4633330002');

INSERT INTO cliente_pf (id_cliente, nome, sobrenome, cpf, data_nascimento) VALUES
 (1,'Rian','Fontoura','12345678901','2000-05-10');

INSERT INTO cliente_pj (id_cliente, razao_social, nome_fantasia, cnpj, inscricao_estadual) VALUES
 (2,'TechParts Comércio LTDA','TechParts','12345678000199','9012345678');

INSERT INTO endereco (id_endereco, id_cliente, logradouro, numero, bairro, cidade, uf, cep) VALUES
 (1,1,'Rua das Flores','100','Centro','Laranjeiras do Sul','PR','85301000'),
 (2,2,'Av. Industrial','500','Distrito','Curitiba','PR','80000000');

INSERT INTO forma_pagamento (id_forma_pagamento, id_cliente, tipo, apelido, bandeira, ultimos_digitos, validade, principal) VALUES
 (1,1,'CARTAO_CREDITO','Cartão Nubank','Mastercard','1234','12/28',TRUE);
INSERT INTO forma_pagamento (id_forma_pagamento, id_cliente, tipo, apelido, chave_pix) VALUES
 (2,1,'PIX','Pix CPF','12345678901'),
 (3,2,'BOLETO','Boleto empresa',NULL);

INSERT INTO produto (id_produto, nome, categoria, valor, quantidade_estoque) VALUES
 (1,'ESP32-C3 Mini','Eletrônicos',39.90,50),
 (2,'Servo SG90','Eletrônicos',12.50,100);

INSERT INTO pedido (id_pedido, id_cliente, id_endereco, status_pedido, frete) VALUES
 (1,1,1,'PAGO',15.00);

INSERT INTO item_pedido VALUES (1,1,2,39.90), (1,2,4,12.50);

-- Pedido pago com DUAS formas de pagamento (cartão + pix)
INSERT INTO pedido_pagamento (id_pedido, id_cliente, id_forma_pagamento, valor, parcelas, status_pagamento) VALUES
 (1,1,1,100.00,2,'APROVADO'),
 (1,1,2, 44.80,1,'APROVADO');

INSERT INTO entrega (id_entrega, id_pedido, transportadora, codigo_rastreio, status_entrega, data_envio, data_previsao) VALUES
 (1,1,'Correios','BR123456789BR','EM_TRANSITO',NOW(),DATE_ADD(CURDATE(), INTERVAL 5 DAY));

INSERT INTO entrega_historico (id_entrega, status_entrega, localizacao) VALUES
 (1,'POSTADO','Laranjeiras do Sul - PR'),
 (1,'EM_TRANSITO','Curitiba - PR');

-- =====================================================
-- CONSULTAS DE VALIDAÇÃO
-- =====================================================

-- 1) Clientes com tipo e documento (PF ou PJ, nunca os dois)
SELECT c.id_cliente, c.tipo_cliente,
       COALESCE(CONCAT(pf.nome,' ',pf.sobrenome), pj.razao_social) AS nome,
       COALESCE(pf.cpf, pj.cnpj) AS documento
FROM cliente c
LEFT JOIN cliente_pf pf ON pf.id_cliente = c.id_cliente
LEFT JOIN cliente_pj pj ON pj.id_cliente = c.id_cliente;

-- 2) Quantas formas de pagamento cada cliente cadastrou
SELECT c.id_cliente, c.email, COUNT(fp.id_forma_pagamento) AS qtd_formas
FROM cliente c
LEFT JOIN forma_pagamento fp ON fp.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.email;

-- 3) Rastreio e status das entregas por pedido
SELECT p.id_pedido, e.transportadora, e.codigo_rastreio, e.status_entrega, e.data_previsao
FROM pedido p
JOIN entrega e ON e.id_pedido = p.id_pedido;

-- 4) Valor total do pedido x total pago
SELECT p.id_pedido,
       SUM(i.quantidade * i.preco_unitario) + p.frete AS total_pedido,
       (SELECT SUM(pp.valor) FROM pedido_pagamento pp
         WHERE pp.id_pedido = p.id_pedido AND pp.status_pagamento = 'APROVADO') AS total_pago
FROM pedido p
JOIN item_pedido i ON i.id_pedido = p.id_pedido
GROUP BY p.id_pedido, p.frete;

-- 5) Entregas por status
SELECT status_entrega, COUNT(*) AS qtd FROM entrega GROUP BY status_entrega;

-- TESTE DE REGRA (descomente: deve FALHAR, cliente 1 é PF e não pode virar PJ)
-- INSERT INTO cliente_pj (id_cliente, razao_social, cnpj) VALUES (1,'Teste','99999999000100');
