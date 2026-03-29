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
