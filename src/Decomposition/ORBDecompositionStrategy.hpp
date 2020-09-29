#ifndef SRC_DECOMPOSITION_ORB_DECOMPOSITION_STRATEGY_HPP
#define SRC_DECOMPOSITION_ORB_DECOMPOSITION_STRATEGY_HPP

#include "Decomposition/AbstractDecompositionStrategy.hpp"

template <unsigned int dim, typename SpaceType,
          typename AbstractDecompositionStrategy =
              AbstractDecompositionStrategy<dim, SpaceType>>
class OrbDecompositionStrategy {

public:
  OrbDecompositionStrategy(Vcluster<> &v_cl) : dec(v_cl) {}

  ~OrbDecompositionStrategy() {}

  /*! \brief Copy constructor
   *
   * \param cart object to copy
   *
   */
  OrbDecompositionStrategy(
      const OrbDecompositionStrategy<dim, SpaceType, AbstractDecompositionStrategy>& cart) {
    this->operator=(cart);
  }

  /*! \brief Copy the element
   *
   * \param cart element to copy
   *
   * \return itself
   *
   */
  OrbDecompositionStrategy<dim, SpaceType> &
  operator=(const AbstractDecompositionStrategy &cart) {
    // todo
  }

  template <typename Model, typename Graph>
  void decompose(Model m, Graph &graph, openfpm::vector<rid> &vtxdist) {
    // todo decompose
  }

  template <typename Graph>
  void merge(Graph &graph, Ghost<dim, SpaceType> &ghost) {
    // todo decompose
  }

private:
  AbstractDecompositionStrategy dec;
};
#endif // SRC_DECOMPOSITION_ORB_DECOMPOSITION_STRATEGY_HPP