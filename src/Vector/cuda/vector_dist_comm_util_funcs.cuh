/*
 * vector_dist_comm_util_funcs.hpp
 *
 *  Created on: Sep 13, 2018
 *      Author: i-bird
 */

#ifndef VECTOR_DIST_COMM_UTIL_FUNCS_HPP_
#define VECTOR_DIST_COMM_UTIL_FUNCS_HPP_

template<unsigned int dim, typename St, typename prop, typename Memory, template<typename> class layout_base, typename Decomposition, bool is_ok_cuda>
struct labelParticlesGhost_impl
{
	static void run(Decomposition & dec,
		    		openfpm::vector<aggregate<unsigned int,unsigned long int>,
		                    CudaMemory,
		                    typename memory_traits_inte<aggregate<unsigned int,unsigned long int>>::type,
		                    memory_traits_inte> & g_opart_device,
		            Vcluster<Memory> & v_cl,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		openfpm::vector<size_t> & prc,
            		openfpm::vector<size_t> & prc_sz,
            		openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & prc_offset,
            		size_t & g_m,
            		size_t opt)
	{
		std::cout << __FILE__ << ":" << __LINE__ << " error, you are trying to use using Cuda functions for a non cuda enabled data-structures" << std::endl;
	}
};



template<unsigned int dim, typename St, typename prop, typename Memory, template<typename> class layout_base, typename Decomposition>
struct labelParticlesGhost_impl<dim,St,prop,Memory,layout_base,Decomposition,true>
{
	static void run(Decomposition & dec,
					openfpm::vector<aggregate<unsigned int,unsigned long int>,
							CudaMemory,
							typename memory_traits_inte<aggregate<unsigned int,unsigned long int>>::type,
							memory_traits_inte> & g_opart_device,
					Vcluster<Memory> & v_cl,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		openfpm::vector<size_t> & prc,
            		openfpm::vector<size_t> & prc_sz,
            		openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & prc_offset,
            		size_t & g_m,
            		size_t opt)
	{
#if defined(CUDA_GPU) && defined(__NVCC__)

            openfpm::vector<aggregate<unsigned int>,
                            Memory,
                            typename layout_base<aggregate<unsigned int>>::type,
                            layout_base> proc_id_out;

			proc_id_out.resize(v_pos.size()+1);
			proc_id_out.template get<0>(proc_id_out.size()-1) = 0;
			proc_id_out.template hostToDevice(proc_id_out.size()-1,proc_id_out.size()-1);

			auto ite = v_pos.getGPUIterator();

			// First we have to see how many entry each particle produce
			num_proc_ghost_each_part<3,St,decltype(dec.toKernel()),decltype(v_pos.toKernel()),decltype(proc_id_out.toKernel())>
			<<<ite.wthr,ite.thr>>>
			(dec.toKernel(),v_pos.toKernel(),proc_id_out.toKernel());

            openfpm::vector<aggregate<unsigned int>,
                            Memory,
                            typename layout_base<aggregate<unsigned int>>::type,
                            layout_base> starts;

			// scan
			scan<unsigned int,unsigned int>(proc_id_out,starts);
			starts.resize(proc_id_out.size());
			starts.template deviceToHost<0>(starts.size()-1,starts.size()-1);
			size_t sz = starts.template get<0>(starts.size()-1);

			// we compute processor id for each particle

		    g_opart_device.resize(sz);

			ite = v_pos.getGPUIterator();

			// we compute processor id for each particle
			proc_label_id_ghost<3,St,decltype(dec.toKernel()),decltype(v_pos.toKernel()),decltype(starts.toKernel()),decltype(g_opart_device.toKernel())>
			<<<ite.wthr,ite.thr>>>
			(dec.toKernel(),v_pos.toKernel(),starts.toKernel(),g_opart_device.toKernel());

			// sort particles
			mergesort((int *)g_opart_device.template getDeviceBuffer<0>(),(long unsigned int *)g_opart_device.template getDeviceBuffer<1>(), g_opart_device.size(), mgpu::template less_t<int>(), v_cl.getmgpuContext());

			CudaMemory mem;
			mem.allocate(sizeof(int));
			mem.fill(0);
			prc_offset.resize(v_cl.size());

			// Find the buffer bases
			find_buffer_offsets<0,decltype(g_opart_device.toKernel()),decltype(prc_offset.toKernel())><<<ite.wthr,ite.thr>>>
					           (g_opart_device.toKernel(),(int *)mem.getDevicePointer(),prc_offset.toKernel());

			// Trasfer the number of offsets on CPU
			mem.deviceToHost();
			prc_offset.template deviceToHost<0,1>();
			g_opart_device.template deviceToHost<0>(g_opart_device.size()-1,g_opart_device.size()-1);

			int noff = *(int *)mem.getPointer();
			prc_offset.resize(noff+1);
			prc_offset.template get<0>(prc_offset.size()-1) = g_opart_device.size();
			prc_offset.template get<1>(prc_offset.size()-1) = g_opart_device.template get<0>(g_opart_device.size()-1);
			prc.resize(noff+1);
			prc_sz.resize(noff+1);

			size_t base_offset = 0;

			// Transfert to prc the list of processors
			prc.resize(noff+1);
			for (size_t i = 0 ; i < noff+1 ; i++)
			{
				prc.get(i) = prc_offset.template get<1>(i);
				prc_sz.get(i) = prc_offset.template get<0>(i) - base_offset;
				base_offset = prc_offset.template get<0>(i);
			}
#else

			std::cout << __FILE__ << ":" << __LINE__ << " error: to use gpu computation you must compile vector_dist.hpp with NVCC" << std::endl;

#endif
	}
};

template<bool with_pos,unsigned int dim, typename St,  typename prop, typename Memory, template <typename> class layout_base, bool is_ok_cuda>
struct local_ghost_from_opart_impl
{
	static void run(openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & o_part_loc,
					const openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & shifts,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		size_t opt)
	{
		std::cout << __FILE__ << ":" << __LINE__ << " error, you are trying to use using Cuda functions for a non cuda enabled data-structures" << std::endl;
	}
};

template<bool with_pos, unsigned int dim, typename St, typename prop, typename Memory, template <typename> class layout_base>
struct local_ghost_from_opart_impl<with_pos,dim,St,prop,Memory,layout_base,true>
{
	static void run(openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & o_part_loc,
					const openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & shifts,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		size_t opt)
	{
#if defined(CUDA_GPU) && defined(__NVCC__)

				auto ite = o_part_loc.getGPUIterator();

				size_t old = v_pos.size();

				v_pos.resize(v_pos.size() + o_part_loc.size(),DATA_ON_DEVICE);
				v_prp.resize(v_prp.size() + o_part_loc.size(),DATA_ON_DEVICE);

				process_ghost_particles_local<with_pos,dim,decltype(o_part_loc.toKernel()),decltype(v_pos.toKernel()),decltype(v_prp.toKernel()),decltype(shifts.toKernel())>
				<<<ite.wthr,ite.thr>>>
				(o_part_loc.toKernel(),v_pos.toKernel(),v_prp.toKernel(),shifts.toKernel(),old);

#else
				std::cout << __FILE__ << ":" << __LINE__ << " error: to use the option RUN_ON_DEVICE you must compile with NVCC" << std::endl;
#endif
	}
};

template<unsigned int dim, typename St, typename prop, typename Memory, template <typename> class layout_base, bool is_ok_cuda>
struct local_ghost_from_dec_impl
{
	static void run(openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & o_part_loc,
					const openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & shifts,
					openfpm::vector<Box<dim, St>,Memory,typename layout_base<Box<dim,St>>::type,layout_base> & box_f_dev,
					openfpm::vector<aggregate<unsigned int>,Memory,typename layout_base<aggregate<unsigned int>>::type,layout_base> & box_f_sv,
					Vcluster<Memory> & v_cl,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		size_t & g_m,
            		size_t opt)
	{
		std::cout << __FILE__ << ":" << __LINE__ << " error, you are trying to use using Cuda functions for a non cuda enabled data-structures" << std::endl;
	}
};


template<unsigned int dim, typename St, typename prop, typename Memory, template <typename> class layout_base>
struct local_ghost_from_dec_impl<dim,St,prop,Memory,layout_base,true>
{
	static void run(openfpm::vector<aggregate<unsigned int,unsigned int>,Memory,typename layout_base<aggregate<unsigned int,unsigned int>>::type,layout_base> & o_part_loc,
					const openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & shifts,
					openfpm::vector<Box<dim, St>,Memory,typename layout_base<Box<dim,St>>::type,layout_base> & box_f_dev,
					openfpm::vector<aggregate<unsigned int>,Memory,typename layout_base<aggregate<unsigned int>>::type,layout_base> & box_f_sv,
					Vcluster<Memory> & v_cl,
					openfpm::vector<Point<dim, St>,Memory,typename layout_base<Point<dim,St>>::type,layout_base> & v_pos,
            		openfpm::vector<prop,Memory,typename layout_base<prop>::type,layout_base> & v_prp,
            		size_t & g_m,
            		size_t opt)
	{
#if defined(CUDA_GPU) && defined(__NVCC__)

		o_part_loc.resize(g_m+1);
		o_part_loc.template get<0>(o_part_loc.size()-1) = 0;
		o_part_loc.template hostToDevice(o_part_loc.size()-1,o_part_loc.size()-1);

		// Label the internal (assigned) particles
		auto ite = v_pos.getGPUIteratorTo(g_m);

		// label particle processor
		num_shift_ghost_each_part<dim,St,decltype(box_f_dev.toKernel()),decltype(v_pos.toKernel()),decltype(o_part_loc.toKernel())>
		<<<ite.wthr,ite.thr>>>
		(box_f_dev.toKernel(),v_pos.toKernel(),o_part_loc.toKernel());

		openfpm::vector<aggregate<unsigned int>,Memory,typename layout_base<aggregate<unsigned int>>::type,layout_base> starts;
		starts.resize(o_part_loc.size());
		mgpu::scan((unsigned int *)o_part_loc.template getDeviceBuffer<0>(), o_part_loc.size(), (unsigned int *)starts.template getDeviceBuffer<0>() , v_cl.getmgpuContext());

		starts.template deviceToHost<0>(starts.size()-1,starts.size()-1);
		size_t total = starts.template get<0>(starts.size()-1);
		size_t old = v_pos.size();

		v_pos.resize(v_pos.size() + total);
		v_prp.resize(v_prp.size() + total);

		// Label the internal (assigned) particles
		ite = v_pos.getGPUIteratorTo(g_m);

		shift_ghost_each_part<dim,St,decltype(box_f_dev.toKernel()),decltype(box_f_sv.toKernel()),
									 decltype(v_pos.toKernel()),decltype(v_prp.toKernel()),
									 decltype(starts.toKernel()),decltype(shifts.toKernel()),
									 decltype(o_part_loc.toKernel())>
		<<<ite.wthr,ite.thr>>>
		(box_f_dev.toKernel(),box_f_sv.toKernel(),
		 v_pos.toKernel(),v_prp.toKernel(),
		 starts.toKernel(),shifts.toKernel(),o_part_loc.toKernel(),old);

#else
		std::cout << __FILE__ << ":" << __LINE__ << " error: to use the option RUN_ON_DEVICE you must compile with NVCC" << std::endl;
#endif
	}
};

#endif /* VECTOR_DIST_COMM_UTIL_FUNCS_HPP_ */
