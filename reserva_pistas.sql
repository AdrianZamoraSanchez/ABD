drop table lineas_factura cascade constraints;
drop table facturas       cascade constraints;
drop table reservas       cascade constraints;
drop table bonos_servicio cascade constraints;
drop table pistas         cascade constraints;
drop table tarifas        cascade constraints;
drop table usuarios       cascade constraints;

drop sequence seq_pistas;
drop sequence seq_reservas;
drop sequence seq_num_fact;

create table usuarios(
    dni       varchar2(9) primary key,
    nombre    varchar2(20) not null,
    ape1      varchar2(20) not null,
    ape2      varchar2(20) not null,
    telefono  varchar2(15)
);

create table tarifas(
    tipo_pista   varchar2(20) primary key,
    precio_hora  number(6,2) not null check (precio_hora >= 0)
);

create sequence seq_pistas;

create table pistas(
    id_pista        number primary key,
    nombre          varchar2(40) not null,
    tipo_pista      varchar2(20) not null references tarifas(tipo_pista),
    capacidad       number not null check (capacidad > 0),
    luz_nocturna    char(1) not null check (luz_nocturna in ('S','N'))
);

create table bonos_servicio(
    codigo_servicio varchar2(10) primary key,
    descripcion     varchar2(40) not null,
    precio_fijo     number(6,2) not null check (precio_fijo >= 0)
);

create sequence seq_reservas;

create table reservas(
    idReserva   number primary key,
    usuario     varchar2(9) not null references usuarios(dni),
    id_pista    number not null references pistas(id_pista),
    fecha_ini   date not null,
    fecha_fin   date not null,
    check (fecha_fin >= fecha_ini)
);

create sequence seq_num_fact;

create table facturas(
    nroFactura  number primary key,
    importe     number(8,2) not null,
    usuario     varchar2(9) not null references usuarios(dni)
);

create table lineas_factura(
    nroFactura  number not null references facturas(nroFactura),
    concepto    varchar2(80) not null,
    importe     number(7,2) not null,
    primary key (nroFactura, concepto)
);
/

create or replace procedure reset_seq(p_seq_name varchar2)
is
    l_val number;
begin
    execute immediate 'select ' || p_seq_name || '.nextval from dual' into l_val;
    execute immediate 'alter sequence ' || p_seq_name || ' increment by -' || l_val || ' minvalue 0';
    execute immediate 'select ' || p_seq_name || '.nextval from dual' into l_val;
    execute immediate 'alter sequence ' || p_seq_name || ' increment by 1 minvalue 0';
end;
/

create or replace procedure inicializa_test is
begin
    begin delete from lineas_factura; exception when others then null; end;
    begin delete from facturas;       exception when others then null; end;
    begin delete from reservas;       exception when others then null; end;
    begin delete from bonos_servicio; exception when others then null; end;
    begin delete from pistas;         exception when others then null; end;
    begin delete from tarifas;        exception when others then null; end;
    begin delete from usuarios;       exception when others then null; end;

    reset_seq('seq_pistas');
    reset_seq('seq_reservas');
    reset_seq('seq_num_fact');

    insert into usuarios values ('12345678A', 'Ana',   'Lopez',  'Martin',  '600111111');
    insert into usuarios values ('11111111B', 'Bruno', 'Perez',  'Santos',  '600222222');
    insert into usuarios values ('22222222C', 'Carla', 'Ruiz',   'Diez',    '600333333');

    insert into tarifas values ('TENIS',   12);
    insert into tarifas values ('PADEL',   16);
    insert into tarifas values ('FUTBOL7', 30);

    insert into bonos_servicio values ('LUZ',  'Iluminacion nocturna', 5);
    insert into bonos_servicio values ('LIMP', 'Limpieza final',       3);

    insert into pistas values (seq_pistas.nextval, 'Pista Central Tenis', 'TENIS',   4,  'S');
    insert into pistas values (seq_pistas.nextval, 'Padel Norte 1',       'PADEL',   4,  'N');
    insert into pistas values (seq_pistas.nextval, 'Campo Azul',          'FUTBOL7', 14, 'S');

    insert into reservas values (
        seq_reservas.nextval,
        '11111111B',
        1,
        to_date('11/03/2026 18:00', 'dd/mm/yyyy hh24:mi'),
        to_date('11/03/2026 20:00', 'dd/mm/yyyy hh24:mi')
    );

    insert into reservas values (
        seq_reservas.nextval,
        '22222222C',
        2,
        to_date('11/03/2026 10:00', 'dd/mm/yyyy hh24:mi'),
        to_date('11/03/2026 11:00', 'dd/mm/yyyy hh24:mi')
    );

    insert into facturas values (seq_num_fact.nextval, 29, '11111111B');
    insert into lineas_factura values (1, 'Reserva de 2 horas de la pista Pista Central Tenis', 24);
    insert into lineas_factura values (1, 'Servicio de iluminacion nocturna', 5);

    insert into facturas values (seq_num_fact.nextval, 16, '22222222C');
    insert into lineas_factura values (2, 'Reserva de 1 horas de la pista Padel Norte 1', 16);

    commit;
end;
/

create or replace procedure reservar_pista(
    arg_dni_usuario        varchar2,
    arg_id_pista           number,
    arg_fecha_ini          date,
    arg_fecha_fin          date,
    arg_incluir_luz        varchar2,
    arg_incluir_limpieza   varchar2
) is
    v_reserva_concurrente  number;
    v_nombre_pista         varchar(40);
    v_tipo_pista           varchar(20);
    v_luz_nocturna         char(1);
    v_num_horas            number;
    v_importe_pista        number;
    v_precio_hora          number;
    v_importe_luz          number;
    v_importe_limp         number;

    ex_usuario_inexistente exception;
    pragma exception_init(ex_usuario_inexistente, -02291); -- ORA-02291: FK padre no encontrado
begin
    -- Validación del intervalo
    if arg_fecha_fin < arg_fecha_ini then
        raise_application_error(-20003, 'El intervalo horario no es valido.');
    end if;

    -- Comprobación de existencia de la pista y bloqueo
    begin
        select nombre, tipo_pista, luz_nocturna
        into v_nombre_pista, v_tipo_pista, v_luz_nocturna
        from pistas
        where id_pista = arg_id_pista
        -- For update permite marcar para update la fila de los datos seleccionados, 
        -- bloqueandolos para evitar que otra transacción concurrente los cambie
        -- garantizando que se trabajan datos consistentes
        for update;
    exception
        when no_data_found then
            raise_application_error(-20002, 'Pista inexistente.');
    end;

    -- Comprobación de disponibilidad.
    select count(*)
        into v_reserva_concurrente
        from reservas r
    where r.id_pista = arg_id_pista
        and r.fecha_ini < arg_fecha_fin
        and r.fecha_fin > arg_fecha_ini;

    if v_reserva_concurrente > 0 then
        raise_application_error(-20004, 'La pista no esta disponible en ese intervalo.');
    end if;

    -- Inserción de la reserva
    begin
        insert into reservas(idReserva, usuario, id_pista, fecha_ini, fecha_fin)
        values (seq_reservas.nextval, arg_dni_usuario, arg_id_pista, arg_fecha_ini, arg_fecha_fin);
    exception
        when ex_usuario_inexistente then
            raise_application_error(-20001, 'Usuario inexistente.');
    end;

    -- TODO
    -- Calculo de importes
    -- Validación de servicio de luz nocturna
    -- Generación de factura
end;
/

create or replace procedure test_reservar_pista is
begin
    begin
        inicializa_test;
        reservar_pista(
            '12345678A',
            1,
            to_date('12/03/2026 12:00', 'dd/mm/yyyy hh24:mi'),
            to_date('12/03/2026 10:00', 'dd/mm/yyyy hh24:mi'),
            'N',
            'N'
        );
        dbms_output.put_line('MAL: intervalo invalido');
    exception
        when others then
            if sqlcode = -20003 then
                dbms_output.put_line('OK: intervalo invalido');
            else
                dbms_output.put_line('MAL: intervalo invalido -> ' || sqlcode || ' ' || sqlerrm);
            end if;
    end;

    begin
        inicializa_test;
        reservar_pista(
            '12345678A',
            999,
            to_date('12/03/2026 10:00', 'dd/mm/yyyy hh24:mi'),
            to_date('12/03/2026 12:00', 'dd/mm/yyyy hh24:mi'),
            'N',
            'N'
        );
        dbms_output.put_line('MAL: pista inexistente');
    exception
        when others then
            if sqlcode = -20002 then
                dbms_output.put_line('OK: pista inexistente');
            else
                dbms_output.put_line('MAL: pista inexistente -> ' || sqlcode || ' ' || sqlerrm);
            end if;
    end;

    begin
        inicializa_test;
        reservar_pista(
            '99999999Z',
            1,
            to_date('12/03/2026 10:00', 'dd/mm/yyyy hh24:mi'),
            to_date('12/03/2026 12:00', 'dd/mm/yyyy hh24:mi'),
            'N',
            'N'
        );
        dbms_output.put_line('MAL: usuario inexistente');
    exception
        when others then
            if sqlcode = -20001 then
                dbms_output.put_line('OK: usuario inexistente');
            else
                dbms_output.put_line('MAL: usuario inexistente -> ' || sqlcode || ' ' || sqlerrm);
            end if;
    end;

    begin
        inicializa_test;
        reservar_pista(
            '12345678A',
            1,
            to_date('11/03/2026 19:00', 'dd/mm/yyyy hh24:mi'),
            to_date('11/03/2026 21:00', 'dd/mm/yyyy hh24:mi'),
            'N',
            'N'
        );
        dbms_output.put_line('MAL: solape');
    exception
        when others then
            if sqlcode = -20004 then
                dbms_output.put_line('OK: solape');
            else
                dbms_output.put_line('MAL: solape -> ' || sqlcode || ' ' || sqlerrm);
            end if;
    end;

    begin
        inicializa_test;
        reservar_pista(
            '12345678A',
            2,
            to_date('12/03/2026 20:00', 'dd/mm/yyyy hh24:mi'),
            to_date('12/03/2026 22:00', 'dd/mm/yyyy hh24:mi'),
            'S',
            'N'
        );
        dbms_output.put_line('MAL: luz no disponible');
    exception
        when others then
            if sqlcode = -20005 then
                dbms_output.put_line('OK: luz no disponible');
            else
                dbms_output.put_line('MAL: luz no disponible -> ' || sqlcode || ' ' || sqlerrm);
            end if;
    end;

    declare
        v_total number;
        v_lineas number;
    begin
        inicializa_test;
        reservar_pista(
            '12345678A',
            1,
            to_date('12/03/2026 20:00', 'dd/mm/yyyy hh24:mi'),
            to_date('12/03/2026 22:00', 'dd/mm/yyyy hh24:mi'),
            'S',
            'S'
        );

        select importe into v_total from facturas where nroFactura = 3;
        select count(*) into v_lineas from lineas_factura where nroFactura = 3;

        if v_total = 32 and v_lineas = 3 then
            dbms_output.put_line('OK: reserva correcta con extras');
        else
            dbms_output.put_line('MAL: reserva correcta con extras -> total=' || v_total || ' lineas=' || v_lineas);
        end if;
    exception
        when others then
            dbms_output.put_line('MAL: reserva correcta con extras -> ' || sqlcode || ' ' || sqlerrm);
    end;
end;
/

set serveroutput on
exec test_reservar_pista;